import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

/// Handles all Firebase Authentication logic.
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Stream of auth state changes — used in main.dart to redirect
  /// between login screen and home screen automatically.
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Returns the currently signed-in Firebase user, or null if not logged in.
  User? get currentUser => _auth.currentUser;

  // ─── Registration ────────────────────────────────────────────────────────

  /// Registers a new user with email/password and a verified phone credential.
  /// Phone verification is mandatory — caller must obtain [phoneCredential]
  /// (e.g. from the SMS code flow) before calling this method.
  ///
  /// If the phone credential turns out to be invalid or already linked to
  /// another account, the freshly created email account is deleted to avoid
  /// orphan accounts.
  Future<UserCredential> registerWithEmail({
    required String email,
    required String password,
    required String username,
    required PhoneAuthCredential phoneCredential,
  }) async {
    // Create Firebase Auth account
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    final newUser = credential.user!;
    try {
      await newUser.linkWithCredential(phoneCredential);
    } catch (e) {
      // Cleanup: delete the orphan email account so the user can retry
      try {
        await newUser.delete();
      } catch (_) {/* ignore secondary failure */}
      rethrow;
    }

    // Save user profile to Firestore with verification expiry set
    final user = UserModel(
      uid: newUser.uid,
      email: email,
      username: username,
      phoneVerifiedUntil: _newPhoneExpiry(),
      createdAt: DateTime.now(),
    );
    await createUserDocument(user);

    return credential;
  }

  // ─── Login ───────────────────────────────────────────────────────────────

  /// Signs in with email and password.
  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    return await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  // ─── Logout ──────────────────────────────────────────────────────────────

  /// Signs out the current user.
  Future<void> signOut() async {
    await _auth.signOut();
  }

  // ─── Identity Verification (Phone) ───────────────────────────────────────

  /// Sends SMS verification code to the given phone number.
  /// codeSent callback provides verificationId needed to complete verification.
  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required void Function(String verificationId) onCodeSent,
    required void Function(String error) onError,
  }) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (PhoneAuthCredential credential) async {
        // Auto-verification (Android only) — link to current account
        await _auth.currentUser?.linkWithCredential(credential);
        await _updatePhoneVerified();
      },
      verificationFailed: (FirebaseAuthException e) {
        onError(e.message ?? 'Verification failed');
      },
      codeSent: (String verificationId, int? resendToken) {
        onCodeSent(verificationId);
      },
      codeAutoRetrievalTimeout: (String verificationId) {},
    );
  }

  /// Verifies the SMS code entered by user and links phone to account.
  Future<void> confirmSmsCode({
    required String verificationId,
    required String smsCode,
  }) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    await _auth.currentUser?.linkWithCredential(credential);
    await _updatePhoneVerified();
  }

  /// Unlinks phone number from current account and clears phoneVerifiedUntil.
  /// Used internally during phone change; not exposed as a user-facing action
  /// because phone verification is mandatory.
  Future<void> unlinkPhone() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await user.unlink('phone');
    await _db.collection('users').doc(user.uid).update({
      'phoneVerifiedUntil': null,
    });
  }

  /// Changes the linked phone number on the current account.
  /// Caller must provide a verified [newCredential] (e.g. from SMS dialog).
  ///
  /// Order: unlink old → link new → update Firestore. If link step fails
  /// (e.g. wrong code or number already in use), Firestore is reset to
  /// unverified so the AuthWrapper consistency check forces re-verification.
  Future<void> changePhoneNumber(PhoneAuthCredential newCredential) async {
    final user = _auth.currentUser;
    if (user == null) return;

    if (user.phoneNumber != null) {
      await user.unlink('phone');
    }

    try {
      await user.linkWithCredential(newCredential);
      await _db.collection('users').doc(user.uid).update({
        'phoneVerifiedUntil': Timestamp.fromDate(_newPhoneExpiry()),
      });
    } catch (e) {
      // Reset to unverified so AuthWrapper will force re-verify
      await _db.collection('users').doc(user.uid).update({
        'phoneVerifiedUntil': null,
      });
      rethrow;
    }
  }

  /// Returns the expiry date for a freshly verified phone number.
  /// Change the duration below to adjust verification expiry period.
  DateTime _newPhoneExpiry() => DateTime.now().add(const Duration(days: 180));

  /// Sets phoneVerifiedUntil to a fresh expiry in Firestore.
  Future<void> _updatePhoneVerified() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _db.collection('users').doc(uid).update({
      'phoneVerifiedUntil': Timestamp.fromDate(_newPhoneExpiry()),
    });
  }

  /// Returns true if [user] has a non-null, non-expired phoneVerifiedUntil.
  /// Used by AuthWrapper and feature gates.
  bool isPhoneVerified(UserModel? user) {
    final until = user?.phoneVerifiedUntil;
    return until != null && until.isAfter(DateTime.now());
  }

  /// Reconciles inconsistent phone state between Firebase Auth and Firestore.
  /// If Firestore says verified but Auth has no phone (e.g. crash mid-change),
  /// clears Firestore so the user is treated as unverified.
  /// Returns the consistent verified-or-not result.
  Future<bool> ensurePhoneConsistency(UserModel userDoc) async {
    final hasPhone = _auth.currentUser?.phoneNumber != null;
    final hasValidExpiry = isPhoneVerified(userDoc);

    if (hasValidExpiry && !hasPhone) {
      await _db.collection('users').doc(userDoc.uid).update({
        'phoneVerifiedUntil': null,
      });
      return false;
    }
    return hasValidExpiry;
  }

  // ─── Profile ─────────────────────────────────────────────────────────────

  /// Updates user profile fields (username, photoUrl) in Firestore.
  Future<void> updateProfile({String? username, String? photoUrl}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final updates = <String, dynamic>{};
    if (username != null) updates['username'] = username;
    if (photoUrl != null) updates['photoUrl'] = photoUrl;
    if (updates.isEmpty) return;
    await _db.collection('users').doc(uid).update(updates);
  }

  /// Changes password for currently signed-in user.
  /// Requires recent login — throws FirebaseAuthException with code
  /// 'requires-recent-login' if user needs to re-authenticate first.
  Future<void> updatePassword(String newPassword) async {
    await _auth.currentUser?.updatePassword(newPassword);
  }

  /// Re-authenticates with current password (needed before sensitive
  /// operations like password change or email change).
  Future<void> reauthenticate(String currentPassword) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) return;
    final credential = EmailAuthProvider.credential(
      email: user.email!,
      password: currentPassword,
    );
    await user.reauthenticateWithCredential(credential);
  }

  /// Sends password reset email — used when user is logged out.
  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  // ─── Firestore helpers ───────────────────────────────────────────────────

  /// Saves a new user document to Firestore at /users/{uid}.
  /// Called after successful registration.
  Future<void> createUserDocument(UserModel user) async {
    await _db.collection('users').doc(user.uid).set(user.toMap());
  }

  /// Fetches the current user's Firestore document.
  Future<UserModel?> getUserDocument(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return UserModel.fromMap(doc.data()!, uid);
  }
}

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

  /// Registers a new user with email/password, creates Firestore user document.
  /// Returns the UserCredential on success, throws FirebaseAuthException on failure.
  Future<UserCredential> registerWithEmail({
    required String email,
    required String password,
    required String username,
  }) async {
    // Create Firebase Auth account
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    // Save user profile to Firestore
    final user = UserModel(
      uid: credential.user!.uid,
      email: email,
      username: username,
      isPhoneVerified: false,
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
        await _updatePhoneVerified(true);
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
    await _updatePhoneVerified(true);
  }

  /// Updates isPhoneVerified in Firestore.
  Future<void> _updatePhoneVerified(bool verified) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _db.collection('users').doc(uid).update({
      'isPhoneVerified': verified,
    });
  }

  // ─── Profile ─────────────────────────────────────────────────────────────

  // TODO: implement profile update, password change, password reset (donghwan/feature/profile)

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

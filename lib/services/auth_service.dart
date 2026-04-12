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
      isEmailVerified: false,
      createdAt: DateTime.now(),
    );
    await createUserDocument(user);

    // Send email verification
    await credential.user!.sendEmailVerification();

    return credential;
  }

  // ─── Login ───────────────────────────────────────────────────────────────

  // TODO: implement email/password login (donghwan/feature/login-logout)
  // TODO: implement Google sign-in (donghwan/feature/login-logout)

  // ─── Logout ──────────────────────────────────────────────────────────────

  // TODO: implement sign out (donghwan/feature/login-logout)

  // ─── Identity Verification ───────────────────────────────────────────────

  // TODO: implement email verification send/check (donghwan/feature/identity-verification)

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

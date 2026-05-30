import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../state/app_settings.dart';
import '../theme/auth_styles.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'phone_verification_screen.dart';

/// Listens to auth state and routes between Login / Phone Verification / Home.
/// - Not logged in → LoginScreen
/// - Logged in but phone unverified or expired → PhoneVerificationRequired
/// - Logged in and verified → HomeScreen
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final _authService = AuthService();

  /// Caches the user-state load so AuthWrapper doesn't refetch on every build.
  /// Bumped via [_reload] after verification or logout to force a refresh.
  int _reloadKey = 0;

  void _reload() => setState(() => _reloadKey++);

  Future<_AuthState> _loadAuthState(String uid) async {
    final user = await _authService.getUserDocument(uid);
    if (user == null) return _AuthState(user: null, isVerified: false);
    final isVerified = await _authService.ensurePhoneConsistency(user);
    // Push seniorMode into app-level state so MaterialApp can react.
    AppSettings.instance.seniorMode.value = user.seniorMode;
    return _AuthState(user: user, isVerified: isVerified);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authService.authStateChanges,
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen();
        }
        final authUser = authSnapshot.data;
        if (authUser == null) {
          return const LoginScreen();
        }

        return FutureBuilder<_AuthState>(
          key: ValueKey(_reloadKey),
          future: _loadAuthState(authUser.uid),
          builder: (context, stateSnapshot) {
            if (stateSnapshot.connectionState == ConnectionState.waiting) {
              return const _LoadingScreen();
            }
            final state = stateSnapshot.data;
            if (state == null || state.user == null) {
              return const _LoadingScreen();
            }
            if (state.isVerified) return const HomeScreen();
            return _PhoneVerificationRequiredScreen(onVerified: _reload);
          },
        );
      },
    );
  }
}

class _AuthState {
  final UserModel? user;
  final bool isVerified;
  _AuthState({required this.user, required this.isVerified});
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

/// Shown when a logged-in user has no valid phone verification.
/// Provides "Verify Phone" (mandatory, can't skip) and "Log Out".
class _PhoneVerificationRequiredScreen extends StatelessWidget {
  final VoidCallback onVerified;
  const _PhoneVerificationRequiredScreen({required this.onVerified});

  Future<void> _verify(BuildContext context) async {
    final ok = await showPhoneVerificationDialog(context, canSkip: false);
    if (ok) onVerified();
  }

  Future<void> _logout(BuildContext context) async {
    await AuthService().signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: const BoxDecoration(
                    color: AuthStyles.badgeGreenBg,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.phone_android,
                    size: 44,
                    color: AuthStyles.badgeGreenText,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Verify your phone',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AuthStyles.darkBg,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                const Text(
                  'To continue using the app, please verify your phone number.',
                  style: TextStyle(
                      fontSize: 14,
                      color: AuthStyles.subtleText,
                      height: 1.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () => _verify(context),
                    style: AuthStyles.primaryPill(),
                    child: const Text('Verify phone'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 52,
                  child: OutlinedButton(
                    onPressed: () => _logout(context),
                    style: AuthStyles.outlinedPill(),
                    child: const Text('Log out'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../theme/auth_styles.dart';
import 'auth_wrapper.dart';
import 'forgot_password_screen.dart';
import 'registration_screen.dart';
import 'welcome_screen.dart';

/// Email/password login. On success, AuthWrapper routes the user onward.
class LoginScreen extends StatefulWidget {
  /// If true, push the registration screen automatically right after this
  /// screen mounts (used when arriving from the onboarding tour's
  /// "Create account" CTA so the user doesn't have to tap "Sign up" again).
  final bool autoOpenRegister;
  const LoginScreen({super.key, this.autoOpenRegister = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.autoOpenRegister) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openRegister();
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _openRegister() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RegistrationScreen()),
    );
  }

  void _openForgotPassword() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
    );
  }

  /// Back always returns to Welcome, regardless of how this screen was
  /// reached (AuthWrapper redirect, onboarding tour, etc.).
  void _backToWelcome() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (_) => false,
    );
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await _authService.signInWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      // Explicitly hand off to AuthWrapper. This path also reaches LoginScreen
      // through Welcome (which replaces the AuthWrapper above us in the tree),
      // so we can't rely on an ancestor StreamBuilder to react to the
      // auth-state change.
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AuthWrapper()),
        (_) => false,
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = _errorFor(e.code));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _errorFor(String code) {
    switch (code) {
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Invalid email or password.';
      default:
        return 'Login failed. Please try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    AuthBackButton(onTap: _backToWelcome),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'Welcome',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AuthStyles.darkBg,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Sign in to continue to your community.',
                  style: TextStyle(
                      fontSize: 14, color: AuthStyles.subtleText, height: 1.5),
                ),
                const SizedBox(height: 28),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _FieldLabel('Email'),
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration:
                              AuthStyles.input('you@neighborhood.app'),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Please enter your email';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 18),
                        const _FieldLabel('Password'),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration:
                              AuthStyles.input('Enter your password').copyWith(
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: AuthStyles.subtleText,
                              ),
                              onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return 'Please enter your password';
                            }
                            return null;
                          },
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _openForgotPassword,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 4),
                            ),
                            child: const Text(
                              'Forgot password?',
                              style: TextStyle(
                                color: AuthStyles.linkBlue,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _errorMessage!,
                            style: const TextStyle(color: Color(0xFFD32F2F)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _login,
                    style: AuthStyles.primaryPill(),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Log in'),
                  ),
                ),
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: _openRegister,
                  child: const Text.rich(
                    TextSpan(
                      text: "Don't have an account? ",
                      style: TextStyle(
                          color: AuthStyles.subtleText, fontSize: 14),
                      children: [
                        TextSpan(
                          text: 'Sign up',
                          style: TextStyle(
                            color: AuthStyles.linkBlue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AuthStyles.darkBg,
        ),
      ),
    );
  }
}

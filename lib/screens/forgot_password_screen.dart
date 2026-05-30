import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/auth_styles.dart';

/// Full-screen forgot-password flow. Sends a Firebase reset email, then
/// shows a confirmation state with a button back to login.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _authService = AuthService();
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  bool _isLoading = false;
  bool _sent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await _authService.sendPasswordResetEmail(_emailController.text.trim());
    } on FirebaseAuthException catch (_) {
      // Generic — don't reveal whether the email exists
    } finally {
      if (mounted) {
        setState(() {
          _sent = true;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  AuthBackButton(onTap: () => Navigator.pop(context)),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                _sent ? 'Check your inbox' : 'Reset password',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AuthStyles.darkBg,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _sent
                    ? 'If an account exists for that email, a reset link has been sent. Please check your inbox.'
                    : 'Enter your account email and we will send you a link to reset your password.',
                style: const TextStyle(
                    fontSize: 14, color: AuthStyles.subtleText, height: 1.5),
              ),
              const SizedBox(height: 28),
              Expanded(
                child: _sent
                    ? const SizedBox.shrink()
                    : SingleChildScrollView(
                        child: Form(
                          key: _formKey,
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
                            ],
                          ),
                        ),
                      ),
              ),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _sent
                      ? () => Navigator.pop(context)
                      : (_isLoading ? null : _send),
                  style: AuthStyles.primaryPill(),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(_sent ? 'Back to log in' : 'Send reset link'),
                ),
              ),
              const SizedBox(height: 8),
            ],
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

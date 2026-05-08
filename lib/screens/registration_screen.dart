import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../theme/profile_styles.dart';
import 'tutorial_screen.dart';

const _smsExpirySeconds = 300; // 5 minutes
const _resendCooldownSeconds = 30;

/// Shows the registration flow as a dialog popup.
/// Phone verification is mandatory and integrated inline with the form.
Future<void> showRegistrationDialog(BuildContext context) async {
  await showDialog(
    context: context,
    builder: (_) => const _RegistrationDialog(),
  );
}

class _RegistrationDialog extends StatefulWidget {
  const _RegistrationDialog();

  @override
  State<_RegistrationDialog> createState() => _RegistrationDialogState();
}

class _RegistrationDialogState extends State<_RegistrationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _smsCodeController = TextEditingController();

  String? _verificationId;
  bool _isSendingSms = false;
  bool _isRegistering = false;
  String? _errorMessage;

  Timer? _expiryTimer;
  int _expirySecondsLeft = 0;
  Timer? _resendTimer;
  int _resendSecondsLeft = 0;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _usernameController.dispose();
    _phoneController.dispose();
    _smsCodeController.dispose();
    _expiryTimer?.cancel();
    _resendTimer?.cancel();
    super.dispose();
  }

  String? _validatePhoneFormat(String input) {
    final pattern = RegExp(r'^\+[1-9]\d{6,14}$');
    if (!pattern.hasMatch(input)) {
      return 'Phone must be in international format (e.g. +821012345678)';
    }
    return null;
  }

  void _startExpiryTimer() {
    _expiryTimer?.cancel();
    setState(() => _expirySecondsLeft = _smsExpirySeconds);
    _expiryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_expirySecondsLeft <= 1) {
        timer.cancel();
        setState(() {
          _expirySecondsLeft = 0;
          _verificationId = null;
        });
      } else {
        setState(() => _expirySecondsLeft--);
      }
    });
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendSecondsLeft = _resendCooldownSeconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendSecondsLeft <= 1) {
        timer.cancel();
        setState(() => _resendSecondsLeft = 0);
      } else {
        setState(() => _resendSecondsLeft--);
      }
    });
  }

  Future<void> _sendSms() async {
    final phone = _phoneController.text.trim();
    final formatError = _validatePhoneFormat(phone);
    if (formatError != null) {
      setState(() => _errorMessage = formatError);
      return;
    }

    setState(() {
      _isSendingSms = true;
      _errorMessage = null;
    });

    await _authService.verifyPhoneNumber(
      phoneNumber: phone,
      onCodeSent: (verificationId) {
        if (!mounted) return;
        setState(() {
          _verificationId = verificationId;
          _isSendingSms = false;
        });
        _startExpiryTimer();
        _startResendCooldown();
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _errorMessage = error;
          _isSendingSms = false;
        });
      },
    );
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (_verificationId == null) {
      setState(() => _errorMessage =
          'Please verify your phone number before creating the account.');
      return;
    }
    if (_smsCodeController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Please enter the SMS verification code.');
      return;
    }

    setState(() {
      _isRegistering = true;
      _errorMessage = null;
    });

    try {
      final phoneCredential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: _smsCodeController.text.trim(),
      );

      await _authService.registerWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        username: _usernameController.text.trim(),
        phoneCredential: phoneCredential,
      );

      _expiryTimer?.cancel();
      _resendTimer?.cancel();

      if (!mounted) return;
      Navigator.pop(context); // close registration dialog
      await showTutorialDialog(context);
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = _getErrorMessage(e.code));
    } catch (_) {
      setState(() => _errorMessage = 'Registration failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isRegistering = false);
    }
  }

  String _getErrorMessage(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'This email is already registered.';
      case 'weak-password':
        return 'Password must be at least 6 characters.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'invalid-verification-code':
      case 'invalid-credential':
        return 'Invalid SMS code. Please try again.';
      case 'credential-already-in-use':
        return 'This phone number is already linked to another account.';
      default:
        return 'Registration failed. Please try again.';
    }
  }

  String _formatTime(int seconds) {
    final m = (seconds ~/ 60).toString();
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final smsSent = _verificationId != null;
    final canRegister = smsSent && !_isRegistering;

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 700),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Create Account',
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold)),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _usernameController,
                  decoration: ProfileStyles.inputDecoration('Username'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a username';
                    }
                    if (value.trim().length < 3) {
                      return 'Username must be at least 3 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: ProfileStyles.inputDecoration('Email'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: ProfileStyles.inputDecoration('Password'),
                  validator: (value) {
                    if (value == null || value.length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(value)) {
                      return 'Password must contain at least one special character';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: true,
                  decoration:
                      ProfileStyles.inputDecoration('Confirm Password'),
                  validator: (value) {
                    if (value != _passwordController.text) {
                      return 'Passwords do not match';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Phone number + Send SMS
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: ProfileStyles.inputDecoration(
                      'Phone (e.g. +821012345678)'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: (_isSendingSms || _resendSecondsLeft > 0)
                      ? null
                      : _sendSms,
                  style: ProfileStyles.outlined,
                  child: _isSendingSms
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_resendSecondsLeft > 0
                          ? 'Resend in ${_resendSecondsLeft}s'
                          : (smsSent ? 'Resend Code' : 'Send Verification Code')),
                ),

                // SMS code field — only shown after code sent
                if (smsSent) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _smsCodeController,
                    keyboardType: TextInputType.number,
                    decoration: ProfileStyles.inputDecoration(
                      _expirySecondsLeft > 0
                          ? 'SMS code (expires in ${_formatTime(_expirySecondsLeft)})'
                          : 'SMS code (expired — tap Resend)',
                    ),
                  ),
                ],

                const SizedBox(height: 24),
                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(_errorMessage!,
                        style: const TextStyle(color: Colors.red)),
                  ),
                ElevatedButton(
                  onPressed: canRegister ? _register : null,
                  style: ProfileStyles.primary,
                  child: _isRegistering
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Create Account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

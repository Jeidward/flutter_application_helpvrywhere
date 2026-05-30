import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/onboarding_prefs.dart';
import '../theme/auth_styles.dart';
import 'auth_wrapper.dart';

const _smsExpirySeconds = 300; // 5 minutes
const _resendCooldownSeconds = 30;

/// Two-step registration:
///   Step 1 — [RegistrationScreen]      account details (username/email/password)
///   Step 2 — [_PhoneVerificationStep]  phone + SMS code → creates the account
///
/// Pushed as a full-screen route (replaces the old `showRegistrationDialog`).
class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _agreedToTerms = false;
  int _passwordStrength = 0; // 0..4

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_recomputeStrength);
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _recomputeStrength() {
    final p = _passwordController.text;
    int score = 0;
    if (p.length >= 8) score++;
    if (RegExp(r'[A-Z]').hasMatch(p)) score++;
    if (RegExp(r'[0-9]').hasMatch(p)) score++;
    if (RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(p)) score++;
    setState(() => _passwordStrength = score);
  }

  /// Short helper that tells the user the next concrete thing to add.
  String _passwordTip() {
    final p = _passwordController.text;
    if (p.isEmpty) return '';
    if (p.length < 6) return 'Too short — use at least 6 characters';
    final missing = <String>[];
    if (!RegExp(r'[0-9]').hasMatch(p)) missing.add('a number');
    if (!RegExp(r'[A-Z]').hasMatch(p)) missing.add('an uppercase letter');
    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(p)) missing.add('a symbol');
    if (p.length < 8) missing.add('more characters');
    if (missing.isEmpty) return 'Strong password';
    switch (_passwordStrength) {
      case 0:
      case 1:
        return 'Weak — add ${missing.first}';
      case 2:
        return 'Fair — add ${missing.first}';
      case 3:
        return 'Good — add ${missing.first} for max strength';
      default:
        return '';
    }
  }

  Color _passwordTipColor() {
    if (_passwordController.text.length < 6) return const Color(0xFFD32F2F);
    switch (_passwordStrength) {
      case 0:
      case 1:
        return const Color(0xFFD32F2F);
      case 2:
        return const Color(0xFFEF6C00);
      case 3:
        return const Color(0xFFB07A00);
      default:
        return const Color(0xFF2E7D32);
    }
  }

  bool get _canContinue {
    return _agreedToTerms &&
        _usernameController.text.trim().length >= 3 &&
        _emailController.text.trim().isNotEmpty &&
        _passwordController.text.length >= 6 &&
        _passwordController.text == _confirmPasswordController.text;
  }

  void _onContinue() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PhoneVerificationStep(
          username: _usernameController.text.trim(),
          email: _emailController.text.trim(),
          password: _passwordController.text,
        ),
      ),
    );
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
            onChanged: () => setState(() {}),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    AuthBackButton(onTap: () => Navigator.pop(context)),
                    const AuthPill('Step 1 of 2'),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'Create your account',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AuthStyles.darkBg,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  "We'll send an SMS code next to verify it's you.",
                  style: TextStyle(
                      fontSize: 14, color: AuthStyles.subtleText, height: 1.5),
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _FieldLabel('Username'),
                        TextFormField(
                          controller: _usernameController,
                          decoration: AuthStyles.input('Your display name'),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Please enter a username';
                            }
                            if (v.trim().length < 3) {
                              return 'At least 3 characters';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 18),
                        _FieldLabel('Email'),
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
                        _FieldLabel('Password'),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: AuthStyles.input('At least 6 characters')
                              .copyWith(
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
                            if (v == null || v.length < 6) {
                              return 'Password must be at least 6 characters';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 10),
                        _PasswordStrengthBar(score: _passwordStrength),
                        if (_passwordTip().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            _passwordTip(),
                            style: TextStyle(
                              fontSize: 12,
                              color: _passwordTipColor(),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        _FieldLabel('Confirm password'),
                        TextFormField(
                          controller: _confirmPasswordController,
                          obscureText: _obscureConfirm,
                          decoration: AuthStyles.input('Re-enter password')
                              .copyWith(
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureConfirm
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: AuthStyles.subtleText,
                              ),
                              onPressed: () => setState(
                                  () => _obscureConfirm = !_obscureConfirm),
                            ),
                          ),
                          validator: (v) {
                            if (v != _passwordController.text) {
                              return 'Passwords do not match';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 22),
                        _TermsCheckbox(
                          checked: _agreedToTerms,
                          onToggle: () => setState(
                              () => _agreedToTerms = !_agreedToTerms),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _canContinue ? _onContinue : null,
                    style: AuthStyles.primaryPill(),
                    child: const Text('Continue'),
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

/// 4-segment password strength bar (length / uppercase / digit / special).
class _PasswordStrengthBar extends StatelessWidget {
  final int score;
  const _PasswordStrengthBar({required this.score});

  Color _segColor(int idx) {
    if (idx >= score) return AuthStyles.cardBorder;
    // 1 = red, 2 = orange, 3 = yellow, 4 = green
    switch (score) {
      case 1:
        return const Color(0xFFE57373);
      case 2:
        return const Color(0xFFFFB74D);
      case 3:
        return const Color(0xFFFFD54F);
      default:
        return const Color(0xFF66BB6A);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(4, (i) {
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i == 3 ? 0 : 6),
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: _segColor(i),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// Terms checkbox with non-functional "Terms" / "Community Code" link styling.
class _TermsCheckbox extends StatelessWidget {
  final bool checked;
  final VoidCallback onToggle;
  const _TermsCheckbox({required this.checked, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: checked ? AuthStyles.linkBlue : Colors.white,
              border: Border.all(
                color:
                    checked ? AuthStyles.linkBlue : AuthStyles.disabledBg,
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(5),
            ),
            child: checked
                ? const Icon(Icons.check, color: Colors.white, size: 16)
                : null,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text.rich(
              TextSpan(
                text: 'I agree to the ',
                style: TextStyle(
                    fontSize: 13, color: AuthStyles.subtleText, height: 1.4),
                children: [
                  TextSpan(
                    text: 'Terms',
                    style: TextStyle(
                      color: AuthStyles.linkBlue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(text: ' & '),
                  TextSpan(
                    text: 'Community Code',
                    style: TextStyle(
                      color: AuthStyles.linkBlue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 2 — phone + SMS code
// ---------------------------------------------------------------------------

class _PhoneVerificationStep extends StatefulWidget {
  final String username;
  final String email;
  final String password;
  const _PhoneVerificationStep({
    required this.username,
    required this.email,
    required this.password,
  });

  @override
  State<_PhoneVerificationStep> createState() => _PhoneVerificationStepState();
}

class _PhoneVerificationStepState extends State<_PhoneVerificationStep> {
  final _authService = AuthService();
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

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
    _phoneController.dispose();
    _codeController.dispose();
    _expiryTimer?.cancel();
    _resendTimer?.cancel();
    super.dispose();
  }

  String? _validatePhone(String input) {
    final pattern = RegExp(r'^\+[1-9]\d{6,14}$');
    if (!pattern.hasMatch(input)) {
      return 'Phone must be in international (E.164) format';
    }
    return null;
  }

  bool get _canSendCode {
    final p = _phoneController.text.trim();
    return p.isNotEmpty &&
        RegExp(r'^\+[1-9]\d{6,14}$').hasMatch(p) &&
        !_isSendingSms &&
        _resendSecondsLeft == 0;
  }

  bool get _canCreate {
    return _verificationId != null &&
        _codeController.text.trim().length >= 4 &&
        !_isRegistering;
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

  Future<void> _sendCode() async {
    final phone = _phoneController.text.trim();
    final formatError = _validatePhone(phone);
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

  Future<void> _createAccount() async {
    if (_verificationId == null) return;
    setState(() {
      _isRegistering = true;
      _errorMessage = null;
    });
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: _codeController.text.trim(),
      );
      final seniorMode = await OnboardingPrefs.getSeniorMode();
      await _authService.registerWithEmail(
        email: widget.email,
        password: widget.password,
        username: widget.username,
        phoneCredential: credential,
        seniorMode: seniorMode,
      );
      await OnboardingPrefs.clear();
      _expiryTimer?.cancel();
      _resendTimer?.cancel();
      if (!mounted) return;
      // Hand off to AuthWrapper. Some entry paths reach this screen with
      // LoginScreen (not AuthWrapper) at the root of the stack, so popping
      // alone would leave the user stuck on LoginScreen post-signup.
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AuthWrapper()),
        (_) => false,
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = _firebaseError(e.code));
    } catch (_) {
      setState(() => _errorMessage = 'Registration failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isRegistering = false);
    }
  }

  String _firebaseError(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'This email is already registered.';
      case 'weak-password':
        return 'Password is too weak.';
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

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  AuthBackButton(onTap: () => Navigator.pop(context)),
                  const AuthPill('Step 2 of 2'),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'Verify your phone',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AuthStyles.darkBg,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'We use phone numbers to keep the community real and safe.\n'
                'Standard SMS rates may apply.',
                style: TextStyle(
                    fontSize: 14, color: AuthStyles.subtleText, height: 1.5),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _FieldLabel('Phone number'),
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        onChanged: (_) => setState(() {}),
                        decoration:
                            AuthStyles.input('+1 (555) 010 1234'),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        smsSent && _expirySecondsLeft > 0
                            ? 'Code expires in ${_formatTime(_expirySecondsLeft)}'
                            : 'E.164 format · 5 min code expiry',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AuthStyles.subtleText,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AuthStyles.badgeGreenBg,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.shield_outlined,
                                  size: 14,
                                  color: AuthStyles.badgeGreenText),
                              SizedBox(width: 6),
                              Text(
                                'Private — never shown publicly',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AuthStyles.badgeGreenText,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (smsSent) ...[
                        const SizedBox(height: 22),
                        _FieldLabel('SMS code'),
                        TextFormField(
                          controller: _codeController,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                          decoration:
                              AuthStyles.input('Enter the 6-digit code'),
                        ),
                      ],
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          style: const TextStyle(color: Color(0xFFD32F2F)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (!smsSent)
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _canSendCode ? _sendCode : null,
                    style: AuthStyles.primaryPill(),
                    child: _isSendingSms
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(_resendSecondsLeft > 0
                            ? 'Resend in ${_resendSecondsLeft}s'
                            : 'Send code'),
                  ),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _canCreate ? _createAccount : null,
                        style: AuthStyles.primaryPill(),
                        child: _isRegistering
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Create account'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        onPressed: _resendSecondsLeft > 0 || _isSendingSms
                            ? null
                            : _sendCode,
                        style: AuthStyles.outlinedPill(),
                        child: Text(_resendSecondsLeft > 0
                            ? 'Resend in ${_resendSecondsLeft}s'
                            : 'Resend code'),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

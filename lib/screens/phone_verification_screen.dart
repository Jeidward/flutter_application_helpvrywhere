import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/auth_styles.dart';

const _codeExpirySeconds = 300; // 5 minutes
const _resendCooldownSeconds = 30;

/// Shows the phone verification flow as a dialog popup.
/// Returns true on successful verification, false if canceled/skipped.
///
/// [canSkip] When true, the dialog can be dismissed without verifying
/// (shows a "Cancel" button). Use false for mandatory verification flows.
///
/// [onVerified] Caller-provided action to run with the verified
/// [PhoneAuthCredential]. The credential is built from the SMS code; if it's
/// invalid, the action throws and the dialog shows the error so the user can
/// retry. Defaults to linking the phone to the current user.
Future<bool> showPhoneVerificationDialog(
  BuildContext context, {
  bool canSkip = true,
  Future<void> Function(PhoneAuthCredential)? onVerified,
}) async {
  final action = onVerified ??
      (cred) => AuthService().linkPhoneToCurrentUser(cred);
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        _PhoneVerificationDialog(canSkip: canSkip, onVerified: action),
  );
  return result == true;
}

class _PhoneVerificationDialog extends StatefulWidget {
  final bool canSkip;
  final Future<void> Function(PhoneAuthCredential) onVerified;
  const _PhoneVerificationDialog({
    required this.canSkip,
    required this.onVerified,
  });

  @override
  State<_PhoneVerificationDialog> createState() =>
      _PhoneVerificationDialogState();
}

class _PhoneVerificationDialogState extends State<_PhoneVerificationDialog> {
  final _authService = AuthService();
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  String? _verificationId;
  bool _codeSent = false;
  bool _isLoading = false;
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

  /// Validates E.164 format: `+[country code][number]`, total 8-16 chars.
  String? _validatePhoneFormat(String input) {
    final pattern = RegExp(r'^\+[1-9]\d{6,14}$');
    if (!pattern.hasMatch(input)) {
      return 'Phone must be in international (E.164) format';
    }
    return null;
  }

  void _startExpiryTimer() {
    _expiryTimer?.cancel();
    setState(() => _expirySecondsLeft = _codeExpirySeconds);
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
          _errorMessage = 'Code expired. Tap Resend to get a new one.';
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
    final formatError = _validatePhoneFormat(phone);
    if (formatError != null) {
      setState(() => _errorMessage = formatError);
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    await _authService.verifyPhoneNumber(
      phoneNumber: phone,
      onCodeSent: (verificationId) {
        if (!mounted) return;
        setState(() {
          _verificationId = verificationId;
          _codeSent = true;
          _isLoading = false;
        });
        _startExpiryTimer();
        _startResendCooldown();
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _errorMessage = error;
          _isLoading = false;
        });
      },
    );
  }

  Future<void> _verifyCode() async {
    if (_verificationId == null) {
      setState(() => _errorMessage = 'Code expired. Tap Resend.');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: _codeController.text.trim(),
      );
      await widget.onVerified(credential);
      _expiryTimer?.cancel();
      _resendTimer?.cancel();
      if (mounted) Navigator.pop(context, true);
    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorMessage = _mapAuthError(e.code);
        _isLoading = false;
      });
    } catch (_) {
      setState(() {
        _errorMessage = 'Verification failed. Please try again.';
        _isLoading = false;
      });
    }
  }

  String _mapAuthError(String code) {
    switch (code) {
      case 'invalid-verification-code':
      case 'invalid-credential':
        return 'Invalid code. Please try again.';
      case 'credential-already-in-use':
        return 'This phone number is already linked to another account.';
      case 'provider-already-linked':
        return 'A phone is already linked to this account.';
      default:
        return 'Verification failed. Please try again.';
    }
  }

  String _formatTime(int seconds) {
    final m = (seconds ~/ 60).toString();
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Verify your phone',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AuthStyles.darkBg,
                    ),
                  ),
                  if (widget.canSkip)
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => Navigator.pop(context, false),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(
                          color: AuthStyles.pillBg,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close,
                            size: 18, color: AuthStyles.darkBg),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (!_codeSent) ...[
                const Text(
                  'We use phone numbers to keep the community real and safe. Standard SMS rates may apply.',
                  style: TextStyle(
                      fontSize: 13,
                      color: AuthStyles.subtleText,
                      height: 1.5),
                ),
                const SizedBox(height: 18),
                const _DialogLabel('Phone number'),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: AuthStyles.input('+1 (555) 010 1234'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'E.164 format · 5 min code expiry',
                  style: TextStyle(
                      fontSize: 12, color: AuthStyles.subtleText),
                ),
                const SizedBox(height: 14),
                const _PrivacyBadge(),
                const SizedBox(height: 20),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _sendCode,
                    style: AuthStyles.primaryPill(),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Send code'),
                  ),
                ),
              ] else ...[
                Text(
                  _expirySecondsLeft > 0
                      ? 'Enter the code we sent. Expires in ${_formatTime(_expirySecondsLeft)}.'
                      : 'Code expired. Tap Resend to get a new one.',
                  style: const TextStyle(
                      fontSize: 13,
                      color: AuthStyles.subtleText,
                      height: 1.5),
                ),
                const SizedBox(height: 18),
                const _DialogLabel('SMS code'),
                TextFormField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  decoration:
                      AuthStyles.input('Enter the 6-digit code'),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed:
                        (_isLoading || _verificationId == null) ? null : _verifyCode,
                    style: AuthStyles.primaryPill(),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Verify'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed:
                        (_isLoading || _resendSecondsLeft > 0) ? null : _sendCode,
                    style: AuthStyles.outlinedPill(),
                    child: Text(_resendSecondsLeft > 0
                        ? 'Resend in ${_resendSecondsLeft}s'
                        : 'Resend code'),
                  ),
                ),
              ],
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Color(0xFFD32F2F)),
                  ),
                ),
              if (widget.canSkip) ...[
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: AuthStyles.subtleText),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogLabel extends StatelessWidget {
  final String text;
  const _DialogLabel(this.text);

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

class _PrivacyBadge extends StatelessWidget {
  const _PrivacyBadge();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AuthStyles.badgeGreenBg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.shield_outlined,
                size: 14, color: AuthStyles.badgeGreenText),
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
    );
  }
}

import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/profile_styles.dart';

const _codeExpirySeconds = 300;   // 5 minutes
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
      return 'Phone must be in international format (e.g. +821012345678)';
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
          _verificationId = null; // invalidate
          _errorMessage = 'Code expired. Please tap Resend to get a new one.';
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
      setState(() => _errorMessage = 'Code expired. Please tap Resend.');
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
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Phone Verification',
                      style: TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold)),
                  if (widget.canSkip)
                    IconButton(
                      onPressed: () => Navigator.pop(context, false),
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (!_codeSent) ...[
                const Text(
                  'Verify your phone number to use the app.',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: ProfileStyles.inputDecoration(
                      'Phone number (e.g. +821012345678)'),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _isLoading ? null : _sendCode,
                  style: ProfileStyles.primary,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Send Verification Code'),
                ),
              ] else ...[
                Text(
                  _expirySecondsLeft > 0
                      ? 'Enter the code sent to your phone. '
                          'Expires in ${_formatTime(_expirySecondsLeft)}.'
                      : 'Code expired. Tap Resend to get a new one.',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  decoration:
                      ProfileStyles.inputDecoration('Verification code'),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed:
                      (_isLoading || _verificationId == null) ? null : _verifyCode,
                  style: ProfileStyles.primary,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Verify'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed:
                      (_isLoading || _resendSecondsLeft > 0) ? null : _sendCode,
                  style: ProfileStyles.outlined,
                  child: Text(_resendSecondsLeft > 0
                      ? 'Resend in ${_resendSecondsLeft}s'
                      : 'Resend Code'),
                ),
              ],
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(_errorMessage!,
                      style: const TextStyle(color: Colors.red)),
                ),
              if (widget.canSkip) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

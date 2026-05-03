import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../theme/profile_styles.dart';
import 'phone_verification_screen.dart';

/// Shows the profile dialog with an internal view switcher (main / edit / change password).
Future<void> showProfileDialog(BuildContext context) async {
  await showDialog(
    context: context,
    builder: (_) => const _ProfileDialog(),
  );
}

enum _View { main, edit, changePassword }

class _ProfileDialog extends StatefulWidget {
  const _ProfileDialog();

  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  final _authService = AuthService();
  Future<UserModel?>? _userFuture;
  _View _currentView = _View.main;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  void _loadUser() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() {
      _userFuture = _authService.getUserDocument(uid);
    });
  }

  void _goTo(_View view) => setState(() => _currentView = view);

  Future<bool> _confirmAction({
    required String title,
    required String content,
    required String actionLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(title),
        content: Text(content),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(actionLabel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _logout() async {
    final ok = await _confirmAction(
      title: 'Log out?',
      content: 'Are you sure you want to log out?',
      actionLabel: 'Log Out',
    );
    if (!ok) return;
    await _authService.signOut();
    if (mounted) {
      Navigator.pop(context);
      Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
    }
  }

  Future<void> _unlinkPhone() async {
    final ok = await _confirmAction(
      title: 'Unlink phone?',
      content: 'You will not be able to use help request features '
          'until you verify your phone again.',
      actionLabel: 'Unlink',
    );
    if (!ok) return;
    await _authService.unlinkPhone();
    _loadUser();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600),
        child: FutureBuilder<UserModel?>(
          future: _userFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final user = snapshot.data;
            if (user == null) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Could not load profile.'),
              );
            }

            switch (_currentView) {
              case _View.main:
                return _buildMain(user);
              case _View.edit:
                return _EditProfileView(
                  initialUser: user,
                  authService: _authService,
                  onBack: () {
                    _loadUser();
                    _goTo(_View.main);
                  },
                );
              case _View.changePassword:
                return _ChangePasswordView(
                  authService: _authService,
                  onBack: () => _goTo(_View.main),
                );
            }
          },
        ),
      ),
    );
  }

  Widget _buildMain(UserModel user) {
    final isVerified = user.phoneVerifiedUntil != null &&
        user.phoneVerifiedUntil!.isAfter(DateTime.now());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Profile',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: CircleAvatar(
              radius: 40,
              backgroundColor: ProfileStyles.avatarBg,
              backgroundImage: user.photoUrl != null
                  ? NetworkImage(user.photoUrl!)
                  : null,
              child: user.photoUrl == null
                  ? const Icon(Icons.person,
                      size: 40, color: ProfileStyles.avatarIcon)
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          _infoRow('Username', user.username),
          const Divider(),
          _infoRow('Email', user.email),
          const Divider(),
          _infoRow(
            'Phone verification',
            isVerified
                ? 'Verified until ${user.phoneVerifiedUntil!.toLocal().toString().split(' ')[0]}'
                : 'Not verified',
          ),
          const SizedBox(height: 8),
          if (isVerified)
            OutlinedButton(
              onPressed: _unlinkPhone,
              style: ProfileStyles.outlined,
              child: const Text('Unlink Phone'),
            )
          else
            ElevatedButton(
              onPressed: () async {
                await showPhoneVerificationDialog(context);
                _loadUser();
              },
              style: ProfileStyles.primary,
              child: const Text('Verify Phone'),
            ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => _goTo(_View.edit),
            style: ProfileStyles.primary,
            child: const Text('Edit Profile'),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () => _goTo(_View.changePassword),
            style: ProfileStyles.primary,
            child: const Text('Change Password'),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _logout,
            style: ProfileStyles.outlined,
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 18)),
        ],
      ),
    );
  }
}

// ─── Edit Profile inline view ────────────────────────────────────────────

class _EditProfileView extends StatefulWidget {
  final UserModel initialUser;
  final AuthService authService;
  final VoidCallback onBack;

  const _EditProfileView({
    required this.initialUser,
    required this.authService,
    required this.onBack,
  });

  @override
  State<_EditProfileView> createState() => _EditProfileViewState();
}

class _EditProfileViewState extends State<_EditProfileView> {
  final _formKey = GlobalKey<FormState>();
  late final _usernameController =
      TextEditingController(text: widget.initialUser.username);
  late final _photoUrlController =
      TextEditingController(text: widget.initialUser.photoUrl ?? '');

  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameController.dispose();
    _photoUrlController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      await widget.authService.updateProfile(
        username: _usernameController.text.trim(),
        photoUrl: _photoUrlController.text.trim().isEmpty
            ? null
            : _photoUrlController.text.trim(),
      );
      widget.onBack();
    } catch (_) {
      setState(() => _errorMessage = 'Could not save changes.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back),
                ),
                const Text('Edit Profile',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _usernameController,
              decoration: ProfileStyles.inputDecoration('Username'),
              validator: (value) {
                if (value == null || value.trim().length < 3) {
                  return 'Username must be at least 3 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _photoUrlController,
              decoration:
                  ProfileStyles.inputDecoration('Photo URL (optional)'),
            ),
            const SizedBox(height: 24),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(_errorMessage!,
                    style: const TextStyle(color: Colors.red)),
              ),
            ElevatedButton(
              onPressed: _isSaving ? null : _save,
              style: ProfileStyles.primary,
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Change Password inline view ─────────────────────────────────────────

class _ChangePasswordView extends StatefulWidget {
  final AuthService authService;
  final VoidCallback onBack;

  const _ChangePasswordView({
    required this.authService,
    required this.onBack,
  });

  @override
  State<_ChangePasswordView> createState() => _ChangePasswordViewState();
}

class _ChangePasswordViewState extends State<_ChangePasswordView> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await widget.authService
          .reauthenticate(_currentPasswordController.text);
      await widget.authService.updatePassword(_newPasswordController.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password changed successfully.')),
        );
        widget.onBack();
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = _getErrorMessage(e.code));
    } catch (_) {
      setState(() => _errorMessage = 'Could not change password.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _getErrorMessage(String code) {
    switch (code) {
      case 'wrong-password':
      case 'invalid-credential':
        return 'Current password is incorrect.';
      case 'weak-password':
        return 'New password is too weak.';
      default:
        return 'Could not change password.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back),
                ),
                const Text('Change Password',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _currentPasswordController,
              obscureText: true,
              decoration: ProfileStyles.inputDecoration('Current password'),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your current password';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _newPasswordController,
              obscureText: true,
              decoration: ProfileStyles.inputDecoration('New password'),
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
                  ProfileStyles.inputDecoration('Confirm new password'),
              validator: (value) {
                if (value != _newPasswordController.text) {
                  return 'Passwords do not match';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(_errorMessage!,
                    style: const TextStyle(color: Colors.red)),
              ),
            ElevatedButton(
              onPressed: _isLoading ? null : _changePassword,
              style: ProfileStyles.primary,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Change Password'),
            ),
          ],
        ),
      ),
    );
  }
}

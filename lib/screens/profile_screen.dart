import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/permissions_service.dart';
import '../state/app_settings.dart';
import '../theme/auth_styles.dart';
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

class _ProfileDialogState extends State<_ProfileDialog>
    with WidgetsBindingObserver {
  final _authService = AuthService();
  final _permService = PermissionsService.instance;
  Future<UserModel?>? _userFuture;
  _View _currentView = _View.main;
  final Map<AppPermission, AppPermissionState> _permStates = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUser();
    _loadPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // After the overlay grant flow leaves for system settings, re-check
    // when we return so the rows reflect the new state.
    if (state == AppLifecycleState.resumed) {
      _loadPermissions();
    }
  }

  void _loadUser() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() {
      _userFuture = _authService.getUserDocument(uid);
    });
  }

  Future<void> _loadPermissions() async {
    final next = <AppPermission, AppPermissionState>{};
    for (final p in PermissionsService.all) {
      next[p] = await _permService.check(p);
    }
    if (!mounted) return;
    setState(() {
      _permStates
        ..clear()
        ..addAll(next);
    });
  }

  Future<void> _onPermissionTapped(AppPermission perm) async {
    final current = _permStates[perm] ?? AppPermissionState.denied;
    AppPermissionState next;
    if (current == AppPermissionState.granted ||
        current == AppPermissionState.permanentlyDenied ||
        current == AppPermissionState.restricted) {
      // Granted state can only be flipped back via system settings, and
      // permanently denied also requires settings. Open it either way.
      await _permService.openSettings();
      return; // lifecycle observer will re-poll on resume
    }
    next = await _permService.request(perm);
    if (!mounted) return;
    setState(() => _permStates[perm] = next);
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
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: AuthStyles.subtleText)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: AuthStyles.primaryPill(),
            child: Text(actionLabel),
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
      actionLabel: 'Log out',
    );
    if (!ok) return;
    await _authService.signOut();
    if (mounted) {
      Navigator.pop(context);
      Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
    }
  }

  Future<void> _changePhone() async {
    final ok = await showPhoneVerificationDialog(
      context,
      canSkip: true,
      onVerified: (cred) => _authService.changePhoneNumber(cred),
    );
    if (ok) _loadUser();
  }

  /// Soft-filled rectangular button used for the main profile actions
  /// (Edit profile / Change password). Lighter visual weight than the
  /// pill primary used in full-screen auth flows.
  static ButtonStyle _softFillButton() => ElevatedButton.styleFrom(
        backgroundColor: AuthStyles.softBlueBg,
        foregroundColor: AuthStyles.linkBlue,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle:
            const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      );

  /// Persist new senior mode value and reflect it app-wide immediately.
  Future<void> _setSeniorMode(bool value) async {
    AppSettings.instance.seniorMode.value = value; // instant UI update
    await _authService.setSeniorMode(value); // persist to Firestore
    _loadUser(); // refresh local user doc
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 640),
        child: FutureBuilder<UserModel?>(
          future: _userFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 240,
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
    final phoneNumber = FirebaseAuth.instance.currentUser?.phoneNumber;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Profile',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AuthStyles.darkBg,
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => Navigator.pop(context),
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
          Center(
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AuthStyles.pillBg,
                border:
                    Border.all(color: AuthStyles.cardBorder, width: 1),
                image: user.photoUrl != null
                    ? DecorationImage(
                        image: NetworkImage(user.photoUrl!),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: user.photoUrl == null
                  ? const Icon(Icons.person,
                      size: 40, color: AuthStyles.subtleText)
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              user.username,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AuthStyles.darkBg,
              ),
            ),
          ),
          const SizedBox(height: 20),
          _InfoCard(children: [
            _InfoRow(label: 'Email', value: user.email),
            const _InfoDivider(),
            _InfoRow(
              label: 'Phone',
              value: phoneNumber ?? 'Not registered',
              trailing: IconButton(
                tooltip: 'Change phone number',
                onPressed: _changePhone,
                icon: const Icon(Icons.edit_outlined,
                    size: 18, color: AuthStyles.linkBlue),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          _InfoCard(children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Senior mode',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AuthStyles.darkBg,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Larger text and simpler screens',
                          style: TextStyle(
                              fontSize: 13,
                              color: AuthStyles.subtleText),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: user.seniorMode,
                    onChanged: _setSeniorMode,
                    activeThumbColor: AuthStyles.linkBlue,
                  ),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              'Permissions',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AuthStyles.subtleText,
                letterSpacing: 0.4,
              ),
            ),
          ),
          _InfoCard(
            children: [
              for (var i = 0; i < PermissionsService.all.length; i++) ...[
                if (i > 0) const _InfoDivider(),
                _PermissionRow(
                  perm: PermissionsService.all[i],
                  state: _permStates[PermissionsService.all[i]] ??
                      AppPermissionState.denied,
                  onTap: () => _onPermissionTapped(
                      PermissionsService.all[i]),
                ),
              ],
            ],
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => _goTo(_View.edit),
            style: _softFillButton(),
            child: const Text('Edit profile'),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () => _goTo(_View.changePassword),
            style: _softFillButton(),
            child: const Text('Change password'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _logout,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFD32F2F),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              side: const BorderSide(color: Color(0xFFFFCDD2)),
              textStyle: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600),
            ),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final List<Widget> children;
  const _InfoCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AuthStyles.cardBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: children),
    );
  }
}

class _InfoDivider extends StatelessWidget {
  const _InfoDivider();

  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, color: AuthStyles.cardBorder);
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Widget? trailing;
  const _InfoRow({required this.label, required this.value, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AuthStyles.subtleText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    color: AuthStyles.darkBg,
                  ),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  final AppPermission perm;
  final AppPermissionState state;
  final VoidCallback onTap;
  const _PermissionRow({
    required this.perm,
    required this.state,
    required this.onTap,
  });

  IconData get _icon {
    switch (perm) {
      case AppPermission.overlay:
        return Icons.layers_outlined;
      case AppPermission.location:
        return Icons.location_on_outlined;
      case AppPermission.microphone:
        return Icons.mic_none_outlined;
    }
  }

  String _statusLabel(bool isRequired) {
    switch (state) {
      case AppPermissionState.granted:
        return 'Granted';
      case AppPermissionState.permanentlyDenied:
      case AppPermissionState.restricted:
        return 'Blocked';
      case AppPermissionState.denied:
        return isRequired ? 'Required' : 'Optional';
    }
  }

  Color _statusColor() {
    switch (state) {
      case AppPermissionState.granted:
        return AuthStyles.badgeGreenText;
      case AppPermissionState.permanentlyDenied:
      case AppPermissionState.restricted:
        return const Color(0xFFD32F2F);
      case AppPermissionState.denied:
        return AuthStyles.subtleText;
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = AppPermissionInfo.of(perm);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            Icon(_icon, size: 20, color: AuthStyles.subtleText),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    info.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AuthStyles.darkBg,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _statusLabel(info.isRequired),
                    style: TextStyle(
                      fontSize: 12,
                      color: _statusColor(),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                size: 18, color: AuthStyles.subtleText),
          ],
        ),
      ),
    );
  }
}

class _DialogFieldLabel extends StatelessWidget {
  final String text;
  const _DialogFieldLabel(this.text);

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
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                AuthBackButton(onTap: widget.onBack),
                const SizedBox(width: 12),
                const Text(
                  'Edit profile',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AuthStyles.darkBg,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const _DialogFieldLabel('Username'),
            TextFormField(
              controller: _usernameController,
              decoration: AuthStyles.input('Your display name'),
              validator: (value) {
                if (value == null || value.trim().length < 3) {
                  return 'Username must be at least 3 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            const _DialogFieldLabel('Photo URL (optional)'),
            TextFormField(
              controller: _photoUrlController,
              decoration: AuthStyles.input('https://...'),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(_errorMessage!,
                  style: const TextStyle(color: Color(0xFFD32F2F))),
            ],
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: AuthStyles.primaryPill(),
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Save'),
              ),
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

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
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

  InputDecoration _passwordDeco(
      String hint, bool obscured, VoidCallback toggle) {
    return AuthStyles.input(hint).copyWith(
      suffixIcon: IconButton(
        icon: Icon(
          obscured
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
          color: AuthStyles.subtleText,
        ),
        onPressed: toggle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                AuthBackButton(onTap: widget.onBack),
                const SizedBox(width: 12),
                const Text(
                  'Change password',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AuthStyles.darkBg,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const _DialogFieldLabel('Current password'),
            TextFormField(
              controller: _currentPasswordController,
              obscureText: _obscureCurrent,
              decoration: _passwordDeco(
                'Enter your current password',
                _obscureCurrent,
                () => setState(() => _obscureCurrent = !_obscureCurrent),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your current password';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            const _DialogFieldLabel('New password'),
            TextFormField(
              controller: _newPasswordController,
              obscureText: _obscureNew,
              decoration: _passwordDeco(
                'At least 6 characters',
                _obscureNew,
                () => setState(() => _obscureNew = !_obscureNew),
              ),
              validator: (value) {
                if (value == null || value.length < 6) {
                  return 'Password must be at least 6 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            const _DialogFieldLabel('Confirm new password'),
            TextFormField(
              controller: _confirmPasswordController,
              obscureText: _obscureConfirm,
              decoration: _passwordDeco(
                'Re-enter new password',
                _obscureConfirm,
                () => setState(() => _obscureConfirm = !_obscureConfirm),
              ),
              validator: (value) {
                if (value != _newPasswordController.text) {
                  return 'Passwords do not match';
                }
                return null;
              },
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(_errorMessage!,
                  style: const TextStyle(color: Color(0xFFD32F2F))),
            ],
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _changePassword,
                style: AuthStyles.primaryPill(),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Change password'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

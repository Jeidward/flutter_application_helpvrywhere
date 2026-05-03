import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';

/// Shows the profile as a dialog popup.
/// Loads user info, displays phone verification status, and provides
/// entry points to edit profile / change password / log out.
Future<void> showProfileDialog(BuildContext context) async {
  await showDialog(
    context: context,
    builder: (_) => const _ProfileDialog(),
  );
}

class _ProfileDialog extends StatefulWidget {
  const _ProfileDialog();

  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  final _authService = AuthService();
  Future<UserModel?>? _userFuture;

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

  Future<bool> _confirmAction({
    required String title,
    required String content,
    required String actionLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
      Navigator.pop(context); // close profile dialog
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

            final isVerified = user.phoneVerifiedUntil != null &&
                user.phoneVerifiedUntil!.isAfter(DateTime.now());

            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header with title and close button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Profile',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Profile photo
                  Center(
                    child: CircleAvatar(
                      radius: 40,
                      backgroundColor: Colors.blueGrey.shade100,
                      backgroundImage: user.photoUrl != null
                          ? NetworkImage(user.photoUrl!)
                          : null,
                      child: user.photoUrl == null
                          ? const Icon(Icons.person, size: 40)
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
                      child: const Text('Unlink Phone'),
                    )
                  else
                    ElevatedButton(
                      onPressed: () async {
                        await Navigator.pushNamed(context, '/verify-phone');
                        _loadUser();
                      },
                      child: const Text('Verify Phone'),
                    ),

                  const SizedBox(height: 24),

                  ElevatedButton(
                    onPressed: () async {
                      await Navigator.pushNamed(context, '/profile/edit');
                      _loadUser();
                    },
                    child: const Text('Edit Profile'),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.pushNamed(
                      context, '/profile/change-password',
                    ),
                    child: const Text('Change Password'),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: _logout,
                    child: const Text('Log Out'),
                  ),
                ],
              ),
            );
          },
        ),
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

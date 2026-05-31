import 'package:flutter/material.dart';
import '../services/permissions_service.dart';
import '../theme/auth_styles.dart';

/// First-launch permission grant screen. Renders cards for each
/// [AppPermission] surfaced by [PermissionsService] and gates Home behind
/// the REQUIRED ones.
///
/// Continue is enabled when every required permission reports
/// [AppPermissionState.granted]. Optional permissions (mic) can be skipped.
class PermissionGateScreen extends StatefulWidget {
  final VoidCallback onAllGranted;
  const PermissionGateScreen({super.key, required this.onAllGranted});

  @override
  State<PermissionGateScreen> createState() => _PermissionGateScreenState();
}

class _PermissionGateScreenState extends State<PermissionGateScreen>
    with WidgetsBindingObserver {
  final _service = PermissionsService.instance;
  final _states = <AppPermission, AppPermissionState>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The overlay grant flow leaves the app for system settings, so we
    // re-check every permission whenever we come back to the foreground.
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final next = <AppPermission, AppPermissionState>{};
    for (final p in PermissionsService.all) {
      next[p] = await _service.check(p);
    }
    if (!mounted) return;
    setState(() {
      _states
        ..clear()
        ..addAll(next);
      _loading = false;
    });
  }

  Future<void> _onCardAction(AppPermission perm) async {
    final current = _states[perm];
    if (current == AppPermissionState.permanentlyDenied ||
        current == AppPermissionState.restricted) {
      await _service.openSettings();
      // didChangeAppLifecycleState will re-poll when we return.
      return;
    }
    final result = await _service.request(perm);
    if (!mounted) return;
    setState(() => _states[perm] = result);
  }

  bool get _canContinue {
    for (final p in PermissionsService.requiredSet) {
      if (_states[p] != AppPermissionState.granted) return false;
    }
    return true;
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
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // No back arrow — the gate is mandatory; the only way
                  // out is to grant the required permissions or log out
                  // (handled by AuthWrapper).
                  SizedBox(width: 40),
                  AuthPill('One-time setup'),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'Set up your permissions',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AuthStyles.darkBg,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                "Grant these once so we don't have to interrupt you mid-task.",
                style: TextStyle(
                    fontSize: 14, color: AuthStyles.subtleText, height: 1.5),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.separated(
                        itemCount: PermissionsService.all.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: 12),
                        itemBuilder: (_, i) {
                          final perm = PermissionsService.all[i];
                          return _PermissionCard(
                            perm: perm,
                            state: _states[perm] ?? AppPermissionState.denied,
                            onAction: () => _onCardAction(perm),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _canContinue ? widget.onAllGranted : null,
                  style: AuthStyles.primaryPill(),
                  child: const Text('Continue'),
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

class _PermissionCard extends StatelessWidget {
  final AppPermission perm;
  final AppPermissionState state;
  final VoidCallback onAction;
  const _PermissionCard({
    required this.perm,
    required this.state,
    required this.onAction,
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

  Color get _iconBg => state == AppPermissionState.granted
      ? AuthStyles.badgeGreenBg
      : AuthStyles.softBlueBg;

  Color get _iconColor => state == AppPermissionState.granted
      ? AuthStyles.badgeGreenText
      : AuthStyles.linkBlue;

  String get _actionLabel {
    if (state == AppPermissionState.permanentlyDenied ||
        state == AppPermissionState.restricted) {
      return 'Open settings';
    }
    return 'Allow';
  }

  @override
  Widget build(BuildContext context) {
    final info = AppPermissionInfo.of(perm);
    final granted = state == AppPermissionState.granted;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: granted ? AuthStyles.badgeGreenBg : Colors.white,
        border: Border.all(
          color: granted ? AuthStyles.badgeGreenText : AuthStyles.cardBorder,
          width: granted ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _iconBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(_icon, color: _iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AuthStyles.darkBg,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _StatusBadge(state: state, isRequired: info.isRequired),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            info.description,
            style: const TextStyle(
              fontSize: 13,
              color: AuthStyles.subtleText,
              height: 1.5,
            ),
          ),
          if (!granted) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 40,
              child: OutlinedButton(
                onPressed: onAction,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AuthStyles.linkBlue,
                  side: const BorderSide(color: AuthStyles.linkBlue),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  textStyle: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
                child: Text(_actionLabel),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final AppPermissionState state;
  final bool isRequired;
  const _StatusBadge({required this.state, required this.isRequired});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    String label;

    if (state == AppPermissionState.granted) {
      bg = AuthStyles.badgeGreenBg;
      fg = AuthStyles.badgeGreenText;
      label = 'Granted';
    } else if (state == AppPermissionState.permanentlyDenied ||
        state == AppPermissionState.restricted) {
      bg = const Color(0xFFFFEAEA);
      fg = const Color(0xFFD32F2F);
      label = 'Blocked';
    } else if (isRequired) {
      bg = const Color(0xFFFFF6E5);
      fg = const Color(0xFFB07A00);
      label = 'Required';
    } else {
      bg = AuthStyles.pillBg;
      fg = AuthStyles.subtleText;
      label = 'Optional';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state == AppPermissionState.granted) ...[
            Icon(Icons.check_circle, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

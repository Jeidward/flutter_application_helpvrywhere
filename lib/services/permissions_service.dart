import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:permission_handler/permission_handler.dart';

/// Identifies a permission we surface to the user in the PermissionGate
/// and the Profile permissions section.
enum AppPermission {
  /// Draw over other apps — required for AI helper highlight bubbles.
  /// Persistent grant via system settings (no runtime dialog).
  overlay,

  /// Foreground location — required to discover nearby help requests.
  /// Persistent grant via runtime dialog.
  location,

  /// Microphone — optional, for voice queries to the AI helper.
  /// Persistent grant via runtime dialog.
  microphone,
}

/// High-level state for a single permission, suitable for UI rendering.
enum AppPermissionState {
  granted,

  /// Denied but the OS will still show a request dialog on next try.
  denied,

  /// Permanently denied (Android "Don't ask again", or >=2 denials on A11+).
  /// User must change the value in system settings — request dialogs no
  /// longer appear.
  permanentlyDenied,

  /// Restricted by parental controls / device policy (iOS / managed device).
  restricted,
}

/// Unified entry point for the three persistent app permissions the user
/// can grant up front (overlay / location / microphone).
///
/// Screen capture is intentionally NOT handled here — it's a per-session
/// `MediaProjection` grant that has to be requested at the moment of first
/// use, and is already wired into the "Ask the AI helper" tile.
class PermissionsService {
  PermissionsService._();
  static final PermissionsService instance = PermissionsService._();

  /// Permissions that gate the rest of the app. The user has to grant
  /// these before reaching Home from the PermissionGate.
  static const requiredSet = <AppPermission>{
    AppPermission.overlay,
    AppPermission.location,
  };

  /// Permissions the user can skip but we still surface in the gate.
  static const optionalSet = <AppPermission>{
    AppPermission.microphone,
  };

  /// All permissions we display in the gate UI / Profile section, in the
  /// order they should appear.
  static const all = <AppPermission>[
    AppPermission.overlay,
    AppPermission.location,
    AppPermission.microphone,
  ];

  Future<AppPermissionState> check(AppPermission perm) async {
    switch (perm) {
      case AppPermission.overlay:
        final granted = await FlutterOverlayWindow.isPermissionGranted();
        return granted
            ? AppPermissionState.granted
            // Overlay has no "permanently denied" runtime concept — the
            // user always grants via system settings, so we collapse the
            // non-granted state to plain `denied`.
            : AppPermissionState.denied;
      case AppPermission.location:
        return _statusToState(await Permission.location.status);
      case AppPermission.microphone:
        return _statusToState(await Permission.microphone.status);
    }
  }

  /// Triggers the OS grant flow appropriate to the permission.
  ///
  /// Returns the *post-request* state — usually [granted] or [denied], but
  /// can be [permanentlyDenied] if the OS suppressed the dialog.
  Future<AppPermissionState> request(AppPermission perm) async {
    switch (perm) {
      case AppPermission.overlay:
        // This launches the system "Display over other apps" settings page.
        // The future completes when the user returns to the app; we then
        // re-check the current grant state.
        await FlutterOverlayWindow.requestPermission();
        final granted = await FlutterOverlayWindow.isPermissionGranted();
        return granted
            ? AppPermissionState.granted
            : AppPermissionState.denied;
      case AppPermission.location:
        return _statusToState(await Permission.location.request());
      case AppPermission.microphone:
        return _statusToState(await Permission.microphone.request());
    }
  }

  /// Opens the OS app-settings page so the user can flip a permanently
  /// denied permission back on. Returns true if the settings screen was
  /// successfully opened.
  Future<bool> openSettings() => openAppSettings();

  /// Convenience — true when every [requiredSet] permission is granted.
  Future<bool> allRequiredGranted() async {
    for (final p in requiredSet) {
      if (await check(p) != AppPermissionState.granted) return false;
    }
    return true;
  }

  AppPermissionState _statusToState(PermissionStatus s) {
    if (s.isGranted || s.isLimited) return AppPermissionState.granted;
    if (s.isPermanentlyDenied) return AppPermissionState.permanentlyDenied;
    if (s.isRestricted) return AppPermissionState.restricted;
    return AppPermissionState.denied;
  }
}

/// UI-facing metadata for each permission (title, blurb, icon hint).
class AppPermissionInfo {
  final String title;
  final String description;
  final bool isRequired;
  const AppPermissionInfo({
    required this.title,
    required this.description,
    required this.isRequired,
  });

  static AppPermissionInfo of(AppPermission p) {
    switch (p) {
      case AppPermission.overlay:
        return const AppPermissionInfo(
          title: 'Display over other apps',
          description:
              'Lets us draw highlight bubbles and step-by-step tips on top of any app.',
          isRequired: true,
        );
      case AppPermission.location:
        return const AppPermissionInfo(
          title: 'Location',
          description:
              'Lets you find help requests from neighbors close to home.',
          isRequired: true,
        );
      case AppPermission.microphone:
        return const AppPermissionInfo(
          title: 'Microphone',
          description:
              'Optional. Lets you ask the AI by voice instead of typing.',
          isRequired: false,
        );
    }
  }
}

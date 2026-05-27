import 'package:flutter/foundation.dart';

/// App-wide UI settings driven by the current user's profile.
/// Held as a singleton so any widget can listen without prop drilling.
///
/// Currently tracks [seniorMode] — when true, the app applies a larger
/// global text scale (see main.dart MaterialApp wrapper) and key screens
/// switch to simplified layouts.
///
/// Updated by AuthWrapper when the user document is loaded, and by Profile
/// when the user toggles senior mode.
class AppSettings {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  /// True = larger text + simplified layouts on key screens.
  final ValueNotifier<bool> seniorMode = ValueNotifier<bool>(false);
}

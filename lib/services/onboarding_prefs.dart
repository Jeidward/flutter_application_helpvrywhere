import 'package:shared_preferences/shared_preferences.dart';

/// Local-only storage for onboarding choices made BEFORE the user has
/// an account (e.g. persona selection on the welcome flow).
///
/// Flow:
/// - User picks persona on the onboarding persona screen → call [setSeniorMode]
/// - User completes sign-up → registration reads [getSeniorMode] and passes
///   it to AuthService.registerWithEmail, then calls [clear] to wipe local state
class OnboardingPrefs {
  static const _kSeniorMode = 'onboarding.seniorMode';
  static const _kWelcomeSeen = 'onboarding.welcomeSeen';

  /// Stores the persona choice (true = senior mode, false = standard).
  static Future<void> setSeniorMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSeniorMode, value);
  }

  /// Reads the stored persona choice. Defaults to false if never set.
  static Future<bool> getSeniorMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kSeniorMode) ?? false;
  }

  /// Wipes the persona choice once it has been persisted to Firestore.
  /// (welcomeSeen is intentionally preserved so Welcome stays hidden.)
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSeniorMode);
  }

  /// Marks that the user has passed through the Welcome screen at least
  /// once on this device, so subsequent launches go straight to AuthWrapper.
  static Future<void> setWelcomeSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kWelcomeSeen, true);
  }

  /// Whether Welcome has ever been seen. Defaults to false (first launch).
  static Future<bool> getWelcomeSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kWelcomeSeen) ?? false;
  }
}

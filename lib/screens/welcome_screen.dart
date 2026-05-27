import 'package:flutter/material.dart';
import '../services/onboarding_prefs.dart';
import 'login_screen.dart';
import 'persona_screen.dart';

/// First-launch entry screen. Two paths:
///  • Get started → Persona → Tour → Registration
///  • Sign in    → LoginScreen (returning user)
///
/// After either path is chosen, the welcomeSeen flag is set so this screen
/// is never shown again on this device (until app data is cleared).
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static const _darkBg = Color(0xFF1A1A1A);
  static const _subtleText = Color(0xFF6B7280);
  static const _linkBlue = Color(0xFF5BA7D9);

  Future<void> _onGetStarted(BuildContext context) async {
    await OnboardingPrefs.setWelcomeSeen();
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PersonaScreen()),
    );
  }

  Future<void> _onSignIn(BuildContext context) async {
    await OnboardingPrefs.setWelcomeSeen();
    if (!context.mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 3),
              // Splash logo + wordmark reused so onboarding feels
              // continuous with launch (same pair as flutter_native_splash).
              // Wordmark already contains the "Community help and request
              // platform" tagline, so no separate subtitle text is needed.
              Center(
                child: Image.asset(
                  'assets/help-vrywhere-logo.png',
                  width: 340,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: Image.asset(
                  'assets/branding.png',
                  width: 260,
                  fit: BoxFit.contain,
                ),
              ),
              const Spacer(flex: 4),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: () => _onGetStarted(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _darkBg,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(32),
                    ),
                  ),
                  child: const Text(
                    'Get started',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => _onSignIn(context),
                child: const Text.rich(
                  TextSpan(
                    text: 'Already have an account? ',
                    style: TextStyle(color: _subtleText, fontSize: 14),
                    children: [
                      TextSpan(
                        text: 'Sign in',
                        style: TextStyle(
                          color: _linkBlue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
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

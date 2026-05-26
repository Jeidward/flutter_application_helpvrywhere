import 'package:flutter/material.dart';
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
              // Centered logo cluster
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: const BoxDecoration(
                        color: _darkBg,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.white,
                        size: 52,
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Decorative people icons under the pin
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.person, color: Color(0xFF6FCF97), size: 22),
                        SizedBox(width: 4),
                        Icon(Icons.person, color: _linkBlue, size: 22),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 36),
              const Text(
                'HelpEverywhere',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: _darkBg,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Your community, ready to help',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: _subtleText),
              ),
              const Spacer(flex: 4),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PersonaScreen()),
                  ),
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
                onTap: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                ),
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

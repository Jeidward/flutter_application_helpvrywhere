import 'package:flutter/material.dart';
import '../services/onboarding_prefs.dart';
import 'auth_wrapper.dart';
import 'welcome_screen.dart';

/// Top-level entry point. Decides whether to show the first-launch
/// Welcome screen or jump straight into AuthWrapper.
///
///   • First launch (welcomeSeen == false) → WelcomeScreen
///   • Subsequent launches (welcomeSeen == true) → AuthWrapper
///
/// AuthWrapper itself decides login vs phone-verify vs home.
class OnboardingGate extends StatefulWidget {
  const OnboardingGate({super.key});

  @override
  State<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<OnboardingGate> {
  late final Future<bool> _welcomeSeenFuture = OnboardingPrefs.getWelcomeSeen();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _welcomeSeenFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final seen = snapshot.data ?? false;
        return seen ? const AuthWrapper() : const WelcomeScreen();
      },
    );
  }
}

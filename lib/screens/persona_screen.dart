import 'package:flutter/material.dart';
import '../services/onboarding_prefs.dart';
import '../state/app_settings.dart';
import 'onboarding_tour_screen.dart';

/// Asks the user to pick a persona before the tour.
/// Two simplified options (team decided to reduce from the original 3):
///   • Just for me  → standard mode (seniorMode = false)
///   • For a senior → senior mode (seniorMode = true, bigger text + easy layouts)
///
/// Choice is stored locally via OnboardingPrefs and read by the registration
/// dialog at sign-up time, then persisted to Firestore.
class PersonaScreen extends StatefulWidget {
  const PersonaScreen({super.key});

  @override
  State<PersonaScreen> createState() => _PersonaScreenState();
}

class _PersonaScreenState extends State<PersonaScreen> {
  static const _darkBg = Color(0xFF1A1A1A);
  static const _subtleText = Color(0xFF6B7280);
  static const _cardBorder = Color(0xFFE5E7EB);
  static const _selectedBorder = Color(0xFF5BA7D9);
  static const _selectedBg = Color(0xFFF0F7FC);
  static const _iconBgMint = Color(0xFFE8F5EE);
  static const _iconBgDark = Color(0xFF1A1A1A);

  // null = nothing picked yet (Continue stays disabled)
  bool? _seniorMode;

  Future<void> _onContinue() async {
    final picked = _seniorMode;
    if (picked == null) return;
    await OnboardingPrefs.setSeniorMode(picked);
    // Apply choice immediately so Tour/Login/Registration preview the
    // chosen text scale. AuthWrapper will re-sync from Firestore after login.
    AppSettings.instance.seniorMode.value = picked;
    if (!mounted) return;
    // Use push (not pushReplacement) so user can return here from Tour.
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const OnboardingTourScreen()),
    );
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
              // Top row: back arrow + "A quick question" pill
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _CircleBackButton(onTap: () => Navigator.pop(context)),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'A quick question',
                      style: TextStyle(fontSize: 12, color: _subtleText),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'Pick the mode that\nfits you best',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: _darkBg,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'This helps us tailor the experience.\nYou can change it later in Settings.',
                style: TextStyle(fontSize: 14, color: _subtleText, height: 1.5),
              ),
              const SizedBox(height: 28),
              _PersonaCard(
                title: 'Standard mode',
                description: 'Default text size and layout.',
                iconBg: _iconBgMint,
                icon: Icons.person_outline,
                iconColor: _darkBg,
                selected: _seniorMode == false,
                onTap: () => setState(() => _seniorMode = false),
                selectedBorder: _selectedBorder,
                cardBorder: _cardBorder,
                selectedBg: _selectedBg,
              ),
              const SizedBox(height: 12),
              _PersonaCard(
                title: 'Senior mode',
                description:
                    'Larger text and simpler layouts to make the app easier to use.',
                iconBg: _iconBgDark,
                icon: Icons.accessibility_new,
                iconColor: Colors.white,
                selected: _seniorMode == true,
                onTap: () => setState(() => _seniorMode = true),
                selectedBorder: _selectedBorder,
                cardBorder: _cardBorder,
                selectedBg: _selectedBg,
              ),
              const Spacer(),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _seniorMode == null ? null : _onContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _darkBg,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFD1D5DB),
                    disabledForegroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(32),
                    ),
                  ),
                  child: const Text(
                    'Continue',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
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

class _CircleBackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CircleBackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          color: Color(0xFFF3F4F6),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.arrow_back_ios_new,
            size: 16, color: Color(0xFF1A1A1A)),
      ),
    );
  }
}

class _PersonaCard extends StatelessWidget {
  final String title;
  final String description;
  final Color iconBg;
  final IconData icon;
  final Color iconColor;
  final bool selected;
  final VoidCallback onTap;
  final Color selectedBorder;
  final Color cardBorder;
  final Color selectedBg;

  const _PersonaCard({
    required this.title,
    required this.description,
    required this.iconBg,
    required this.icon,
    required this.iconColor,
    required this.selected,
    required this.onTap,
    required this.selectedBorder,
    required this.cardBorder,
    required this.selectedBg,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? selectedBg : Colors.white,
          border: Border.all(
            color: selected ? selectedBorder : cardBorder,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconBg,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF6B7280),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? selectedBorder : const Color(0xFFD1D5DB),
                  width: 2,
                ),
                color: selected ? selectedBorder : Colors.transparent,
              ),
              child: selected
                  ? const Icon(Icons.check, color: Colors.white, size: 14)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

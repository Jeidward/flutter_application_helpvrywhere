import 'package:flutter/material.dart';

/// Shared design tokens for the auth + onboarding flow
/// (Welcome / Persona / Tour / Sign-up / SMS / Login / Forgot password).
///
/// The older `profile_styles.dart` uses a different palette and will be
/// migrated to match this in a later step.
class AuthStyles {
  static const darkBg = Color(0xFF1A1A1A);
  static const subtleText = Color(0xFF6B7280);
  static const linkBlue = Color(0xFF5BA7D9);
  static const cardBorder = Color(0xFFE5E7EB);
  static const disabledBg = Color(0xFFD1D5DB);
  static const pillBg = Color(0xFFF3F4F6);
  static const badgeGreenBg = Color(0xFFE8F5EE);
  static const badgeGreenText = Color(0xFF1E7D45);

  static InputDecoration input(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 15),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: linkBlue, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE57373)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE57373), width: 2),
        ),
      );

  /// Pill-shaped primary CTA. Disabled state is rendered automatically by
  /// passing `onPressed: null`.
  static ButtonStyle primaryPill({Color background = linkBlue}) =>
      ElevatedButton.styleFrom(
        backgroundColor: background,
        foregroundColor: Colors.white,
        disabledBackgroundColor: disabledBg,
        disabledForegroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      );

  static ButtonStyle outlinedPill() => OutlinedButton.styleFrom(
        foregroundColor: darkBg,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        side: const BorderSide(color: cardBorder),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      );
}

/// Small circular back button reused across welcome / persona / sign-up.
class AuthBackButton extends StatelessWidget {
  final VoidCallback onTap;
  const AuthBackButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          color: AuthStyles.pillBg,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.arrow_back_ios_new,
            size: 16, color: AuthStyles.darkBg),
      ),
    );
  }
}

/// Tiny gray pill ("Step 1 of 2", "A quick question", etc.).
class AuthPill extends StatelessWidget {
  final String text;
  const AuthPill(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AuthStyles.pillBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: AuthStyles.subtleText),
      ),
    );
  }
}

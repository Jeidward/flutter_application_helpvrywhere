import 'package:flutter/material.dart';

/// Soft pastel palette + button styles for profile-related screens,
/// matching the prototype design tone.
class ProfileStyles {
  static const accent = Color(0xFF1A73E8);
  static const softBlueBg = Color(0xFFE8F0FE);
  static const avatarBg = Color(0xFFEBE8FE);
  static const avatarIcon = Color(0xFF6B5DD3);

  static ButtonStyle get primary => ElevatedButton.styleFrom(
        backgroundColor: softBlueBg,
        foregroundColor: accent,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );

  static ButtonStyle get outlined => OutlinedButton.styleFrom(
        foregroundColor: accent,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: const BorderSide(color: Color(0xFFE0E0E0)),
      );

  static InputDecoration inputDecoration(String label) => InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accent, width: 2),
        ),
      );
}

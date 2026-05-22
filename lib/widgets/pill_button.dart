import 'package:flutter/material.dart';
import 'package:flutter_application_helpvrywhere/theme/app_theme.dart';

/// Pill-shaped primary or outline button used throughout the
/// nearby-request flow ("I can help", "Directions", "Offer help", etc.).
class PillButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool primary;
  final double height;
  final double fontSize;
  final Color? color;

  const PillButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.primary = true,
    this.height = 38,
    this.fontSize = 13,
    this.color,
  });

  factory PillButton.primary({
    Key? key,
    required String label,
    IconData? icon,
    VoidCallback? onPressed,
    double height = 38,
    double fontSize = 13,
    Color? color,
  }) =>
      PillButton(
        key: key,
        label: label,
        icon: icon,
        onPressed: onPressed,
        primary: true,
        height: height,
        fontSize: fontSize,
        color: color,
      );

  factory PillButton.outline({
    Key? key,
    required String label,
    IconData? icon,
    VoidCallback? onPressed,
    double height = 38,
    double fontSize = 13,
  }) =>
      PillButton(
        key: key,
        label: label,
        icon: icon,
        onPressed: onPressed,
        primary: false,
        height: height,
        fontSize: fontSize,
      );

  @override
  Widget build(BuildContext context) {
    final bg = primary ? (color ?? AppColors.primaryBlue) : AppColors.surface;
    final fg = primary ? Colors.white : AppColors.darkNavy;

    return SizedBox(
      height: height,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          side: primary
              ? BorderSide.none
              : const BorderSide(color: AppColors.border, width: 1.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: fontSize + 2, color: fg),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w700,
                    color: fg,
                    letterSpacing: -0.13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

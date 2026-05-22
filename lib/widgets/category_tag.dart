import 'package:flutter/material.dart';
import 'package:flutter_application_helpvrywhere/models/nearby_request.dart';
import 'package:flutter_application_helpvrywhere/theme/app_theme.dart';

/// Coloured tag pill ("Household", "Groceries", "~10 min", etc.)
class CategoryTag extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color foreground;
  final Color background;
  final FontWeight fontWeight;

  const CategoryTag({
    super.key,
    required this.label,
    this.icon,
    required this.foreground,
    required this.background,
    this.fontWeight = FontWeight.w700,
  });

  factory CategoryTag.fromCategory(RequestCategory category) => CategoryTag(
        label: category.label,
        icon: category.icon,
        foreground: category.foreground,
        background: category.background,
      );

  /// Neutral time/meta pill (e.g. "~10 min")
  factory CategoryTag.meta(String label, {IconData? icon}) => CategoryTag(
        label: label,
        icon: icon,
        foreground: AppColors.darkNavy,
        background: const Color(0xFFF4F5F8),
        fontWeight: FontWeight.w600,
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: foreground),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: fontWeight,
              color: foreground,
              letterSpacing: -0.055,
            ),
          ),
        ],
      ),
    );
  }
}

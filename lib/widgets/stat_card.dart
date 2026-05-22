import 'package:flutter/material.dart';
import 'package:flutter_application_helpvrywhere/theme/app_theme.dart';

/// Colour tint used by [StatCard]. Maps to one of the brand colour
/// pairs (foreground icon + background tint).
enum StatTint { blue, green, neutral }

/// One of the 3-up summary tiles (e.g. Posted / Distance / Replies).
///
/// Used on the request detail screen + future dashboards to highlight a
/// single metric. Picks its colours from [AppColors] via [StatTint] so
/// every screen stays on-brand.
class StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final StatTint tint;

  const StatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.tint = StatTint.neutral,
  });

  (Color, Color) get _tintColors => switch (tint) {
        StatTint.blue => (AppColors.primaryBlue, AppColors.lightBlue),
        StatTint.green => (AppColors.primaryGreen, AppColors.lightGreen),
        StatTint.neutral => (AppColors.darkNavy, const Color(0xFFF4F5F8)),
      };

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = _tintColors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.tile),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 15, color: fg),
          ),
          const SizedBox(height: 10),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.darkNavy,
              letterSpacing: -0.15,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

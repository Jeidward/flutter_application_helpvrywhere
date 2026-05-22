import 'package:flutter/material.dart';
import 'package:flutter_application_helpvrywhere/theme/app_theme.dart';

/// Green community-tone safety note with a shield-check icon. Used on
/// the request detail screen to remind volunteers about safe meet-ups.
class SafetyBanner extends StatelessWidget {
  final String title;
  final String body;

  const SafetyBanner({
    super.key,
    this.title = 'Stay safe',
    this.body =
        'Meet in public, share live location with someone you trust, and never share financial information.',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.lightGreen,
        border: Border.all(color: AppColors.primaryGreen.withOpacity(0.2)),
        borderRadius: BorderRadius.circular(AppRadius.tile),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primaryGreen.withOpacity(0.18),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.verified_user_outlined,
              size: 16,
              color: AppColors.primaryGreen,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.safetyTitle,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: AppColors.safetyText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

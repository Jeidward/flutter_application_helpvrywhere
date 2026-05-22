import 'package:flutter/material.dart';
import 'package:flutter_application_helpvrywhere/models/nearby_request.dart';
import 'package:flutter_application_helpvrywhere/theme/app_theme.dart';
import 'package:flutter_application_helpvrywhere/widgets/category_tag.dart';
import 'package:flutter_application_helpvrywhere/widgets/pill_button.dart';

/// Polished card used in the Nearby Requests feed.
///
/// Pulls from the shared brand widgets ([CategoryTag], [PillButton]) and
/// the [AppColors] palette so the look stays consistent with the rest of
/// the volunteer flow. The pulse dot picks up the request category's
/// foreground colour for a subtle category cue.
class RequestCard extends StatelessWidget {
  final NearbyRequest request;
  final VoidCallback? onTap;
  final VoidCallback? onOffer;
  final VoidCallback? onDirections;

  const RequestCard({
    super.key,
    required this.request,
    this.onTap,
    this.onOffer,
    this.onDirections,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final hasDistance = request.distanceKm > 0;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row — pulse dot, title, subtitle, time-ago
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 8, right: 10),
                    // Pulse dot is the same brand blue for every category —
                    // category is communicated by the coloured pill below.
                    child: _PulseDot(color: AppColors.primaryBlue),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          request.title,
                          style: t.titleSmall?.copyWith(
                            fontSize: 16,
                            height: 1.25,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          hasDistance
                              ? '${request.requesterName} · ${request.distanceLabel} away'
                              : request.requesterName,
                          style: t.bodySmall?.copyWith(fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      request.postedShort,
                      style: t.bodySmall?.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // Tags row — category + estimated time
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  CategoryTag.fromCategory(request.category),
                  if (hasDistance)
                    CategoryTag.meta(
                      request.estimatedLabel,
                      icon: Icons.access_time_rounded,
                    ),
                ],
              ),

              const SizedBox(height: 14),

              // Actions
              Row(
                children: [
                  Expanded(
                    child: PillButton.primary(
                      label: 'I can help',
                      height: 44,
                      fontSize: 14,
                      onPressed: onOffer,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: PillButton.outline(
                      label: 'Directions',
                      icon: Icons.near_me_outlined,
                      height: 44,
                      fontSize: 14,
                      onPressed: onDirections,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pulsing colour dot used as the category cue on the card header.
class _PulseDot extends StatefulWidget {
  final Color color;
  const _PulseDot({required this.color});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (ctx, _) {
        final t = _ctrl.value;
        final ringScale = 1.0 + 3.0 * t;
        final ringOpacity = (1.0 - t).clamp(0.0, 1.0) * 0.4;
        return SizedBox(
          width: 10,
          height: 10,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Transform.scale(
                scale: ringScale,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withOpacity(ringOpacity),
                  ),
                ),
              ),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

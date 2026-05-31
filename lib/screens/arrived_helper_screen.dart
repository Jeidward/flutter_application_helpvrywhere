import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_helpvrywhere/models/trip.dart';
import 'package:flutter_application_helpvrywhere/services/trip_service.dart';
import 'package:flutter_application_helpvrywhere/theme/app_theme.dart';
import 'package:flutter_application_helpvrywhere/widgets/pill_button.dart';

/// Step 4 (helper side) — "You've arrived" calm white screen shown
/// when the geofence triggers (or the helper manually taps "I'm at
/// the door" from the live nav).
///
/// Pushes the trip status to [TripStatus.atDoor] on first build (if
/// it isn't already), so the requester's phone immediately swaps to
/// the "Margaret is here — verify the code" screen.
///
/// Tapping "I'm at the door" then pops back to the home screen — the
/// trip stays in `atDoor` until the requester confirms with the code.
class ArrivedHelperScreen extends StatefulWidget {
  const ArrivedHelperScreen({
    super.key,
    required this.trip,
    required this.requesterName,
    required this.doorLabel,
  });

  final Trip trip;
  final String requesterName;

  /// Free-text address detail to render under the title, e.g.
  /// "Apartment 4F · doorbell #1421". When not available (most live
  /// requests don't have a structured door number), pass the
  /// neighborhood / address string and the screen will degrade
  /// gracefully.
  final String doorLabel;

  @override
  State<ArrivedHelperScreen> createState() => _ArrivedHelperScreenState();
}

class _ArrivedHelperScreenState extends State<ArrivedHelperScreen> {
  bool _announced = false;

  @override
  void initState() {
    super.initState();
    // Push status to atDoor the moment this screen appears.
    _announceArrival();
  }

  Future<void> _announceArrival() async {
    if (widget.trip.status == TripStatus.atDoor ||
        widget.trip.status == TripStatus.completed) {
      _announced = true;
      return;
    }
    try {
      await TripService()
          .updateStatus(widget.trip.id, TripStatus.atDoor);
      _announced = true;
    } on FirebaseException catch (_) {
      // Silently fail — the requester just won't see the swap. The
      // tap on "I'm at the door" below will retry.
    }
  }

  Future<void> _onAtDoor() async {
    final messenger = ScaffoldMessenger.of(context);
    if (!_announced) {
      try {
        await TripService()
            .updateStatus(widget.trip.id, TripStatus.atDoor);
        _announced = true;
      } catch (_) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Could not notify the requester.')),
        );
        return;
      }
    }
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Back chip (small, calm).
              Material(
                color: const Color(0xFFF5F6F8),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.maybePop(context),
                  child: const SizedBox(
                    width: 34,
                    height: 34,
                    child: Icon(Icons.arrow_back, size: 18),
                  ),
                ),
              ),
              const Spacer(),

              // 140px pulsing green halo with a pin-with-check icon.
              Center(child: _ArrivalIcon()),
              const SizedBox(height: 24),

              const Text(
                "You've arrived",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                "${widget.requesterName}'s place is just ahead — "
                "${widget.doorLabel}. Show them the trip code when you knock.",
                style: const TextStyle(
                  fontSize: 15,
                  color: AppColors.muted,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),

              // "Who you're meeting" strip — requester avatar +
              // trip code + "is expecting you" copy. Avatar shows
              // the requester's initial in a green circle to match
              // the design (small "L" for Mrs. Lee in the handoff).
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F6F8),
                  borderRadius: BorderRadius.circular(AppRadius.tile),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: AppColors.lightGreen,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        _initialsOf(widget.requesterName),
                        style: const TextStyle(
                          color: AppColors.primaryGreen,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Trip ${widget.trip.code}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w700,
                              color: AppColors.darkNavy,
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${widget.requesterName} is expecting you',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.muted,
                              fontWeight: FontWeight.w500,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),

              // Action row — primary CTA gets more room than the
              // secondary "Message" pill. 3:2 flex (instead of 2:1)
              // gives the Message button enough width to fit its
              // icon + label without the icon clipping at the edge.
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: PillButton.primary(
                      label: "I'm at the door",
                      icon: Icons.check_circle_rounded,
                      height: 54,
                      fontSize: 16,
                      color: AppColors.primaryGreen,
                      onPressed: _onAtDoor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: PillButton.outline(
                      label: 'Message',
                      icon: Icons.chat_bubble_outline_rounded,
                      height: 54,
                      fontSize: 16,
                      onPressed: () {
                        // Wired by the screen that opens this one if needed.
                      },
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

/// "Mrs. Lee" → "ML". Single word → first letter. Used by the trip
/// strip's small requester avatar.
String _initialsOf(String name) {
  final parts =
      name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

class _ArrivalIcon extends StatefulWidget {
  @override
  State<_ArrivalIcon> createState() => _ArrivalIconState();
}

class _ArrivalIconState extends State<_ArrivalIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2500),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      height: 160,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (ctx, _) {
              final t = _pulse.value;
              final scale = 0.9 + 0.5 * t;
              final op = (0.5 - 0.5 * t).clamp(0.0, 0.5);
              return Transform.scale(
                scale: scale,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primaryGreen.withOpacity(op),
                  ),
                ),
              );
            },
          ),
          Container(
            width: 140,
            height: 140,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.lightGreen,
            ),
            child: const Icon(
              Icons.location_on_rounded,
              size: 64,
              color: AppColors.primaryGreen,
            ),
          ),
        ],
      ),
    );
  }
}

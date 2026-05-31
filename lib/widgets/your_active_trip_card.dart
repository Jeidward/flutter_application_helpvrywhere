import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_helpvrywhere/models/trip.dart';
import 'package:flutter_application_helpvrywhere/screens/request_detail_screen.dart';
import 'package:flutter_application_helpvrywhere/services/trip_service.dart';
import 'package:flutter_application_helpvrywhere/services/user_service.dart';
import 'package:flutter_application_helpvrywhere/theme/app_theme.dart';

/// "You're helping" home-tab card — the helper-side counterpart to
/// [YourRequestCard].
///
/// Surfaces the volunteer's most-recent *in-progress* trip (status
/// confirmed / enRoute / atDoor) so a trip they backed out of (or
/// backgrounded mid-route) can always be resumed from home. This is the
/// dedicated home button that replaced the old green "You're helping X"
/// banner on the nearby-requests map — keeping the map focused on
/// browsing and the helper's commitment visible where they land.
///
/// Renders:
///   • Header: "You're helping"  +  a status chip (Ready / On the way /
///     At the door) with a live green pulse dot once the trip is moving
///   • "{Requester} needs your help" (name resolved from `users`)
///   • The trip code ("BLU · 47") so it matches what the requester sees
///   • A green action pill whose label tracks the trip status
///
/// Returns an empty box when the user has no active trip, so it doesn't
/// take up space on the home tab when not relevant.
///
/// Tapping opens the request detail screen by id — for the accepted
/// helper that screen shows "Start navigation", so the existing,
/// well-tested resume path is reused rather than duplicated here.
class YourActiveTripCard extends StatelessWidget {
  const YourActiveTripCard({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<List<Trip>>(
      stream: TripService().watchActiveForHelper(uid),
      builder: (ctx, snap) {
        final trips = [...(snap.data ?? const <Trip>[])]
          // Service intentionally omits orderBy (avoids a composite
          // index), so we pick the most-recent trip client-side.
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        if (trips.isEmpty) return const SizedBox.shrink();
        final trip = trips.first;

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _TripCardBody(trip: trip),
        );
      },
    );
  }
}

class _TripCardBody extends StatelessWidget {
  const _TripCardBody({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: () => RequestDetailScreen.openById(context, trip.requestId),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppRadius.card),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header — "You're helping" + status chip
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      "You're helping",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.darkNavy,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  _TripStatusChip(status: trip.status),
                ],
              ),
              const SizedBox(height: 12),

              // Requester name — resolved lazily from the users collection.
              FutureBuilder<String>(
                future: _resolveRequesterName(trip.requesterUid),
                builder: (ctx, snap) {
                  final name = (snap.data ?? '').trim();
                  final who = name.isNotEmpty ? name : 'Your neighbour';
                  return Text(
                    '$who needs your help',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.darkNavy,
                      letterSpacing: -0.2,
                      height: 1.25,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  );
                },
              ),
              const SizedBox(height: 6),

              // Trip code — matches what the requester sees so they can
              // verify "is this really my helper?" at the door.
              Text(
                'Trip code · ${trip.code}',
                style: const TextStyle(
                  fontSize: 13.5,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),

              const SizedBox(height: 14),

              // Action pill — label tracks the trip status.
              _ResumePill(status: trip.status),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small status chip on the header row. Static for `confirmed`; gains a
/// pulsing green dot once the trip is live (enRoute / atDoor) to echo
/// the "live" feel of the requester's card.
class _TripStatusChip extends StatefulWidget {
  const _TripStatusChip({required this.status});

  final TripStatus status;

  @override
  State<_TripStatusChip> createState() => _TripStatusChipState();
}

class _TripStatusChipState extends State<_TripStatusChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final live = widget.status == TripStatus.enRoute ||
        widget.status == TripStatus.atDoor;
    final label = switch (widget.status) {
      TripStatus.confirmed => 'READY',
      TripStatus.enRoute => 'ON THE WAY',
      TripStatus.atDoor => 'AT THE DOOR',
      TripStatus.completed => 'DONE',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.lightGreen,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (live)
            AnimatedBuilder(
              animation: _pulse,
              builder: (ctx, _) {
                final op = 0.4 + 0.6 * _pulse.value;
                return Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primaryGreen.withOpacity(op),
                  ),
                );
              },
            )
          else
            const Icon(
              Icons.volunteer_activism_rounded,
              size: 13,
              color: AppColors.primaryGreen,
            ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: AppColors.primaryGreen,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

/// Green pill whose icon + label reflect what tapping the card will do
/// next, given the current trip status.
class _ResumePill extends StatelessWidget {
  const _ResumePill({required this.status});

  final TripStatus status;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (status) {
      TripStatus.confirmed => (
          Icons.navigation_rounded,
          'Tap to start navigation',
        ),
      TripStatus.enRoute => (
          Icons.navigation_rounded,
          'Resume navigation',
        ),
      TripStatus.atDoor => (
          Icons.door_front_door_rounded,
          "Tap to confirm you've arrived",
        ),
      TripStatus.completed => (
          Icons.check_circle_rounded,
          'Trip complete',
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.lightGreen,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.primaryGreen),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryGreen,
                letterSpacing: -0.13,
              ),
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: AppColors.primaryGreen,
          ),
        ],
      ),
    );
  }
}

/// Resolves the requester's display name from the `users` collection.
/// Returns an empty string on any miss so the card can fall back to a
/// neutral "Your neighbour".
Future<String> _resolveRequesterName(String uid) async {
  try {
    final name = await UserService().getUsername(uid);
    if (name.isEmpty || name == 'Unknown') return '';
    return name;
  } catch (_) {
    return '';
  }
}

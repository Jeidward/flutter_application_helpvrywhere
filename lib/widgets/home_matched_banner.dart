import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_helpvrywhere/models/trip.dart';
import 'package:flutter_application_helpvrywhere/screens/arrived_requester_screen.dart';
import 'package:flutter_application_helpvrywhere/services/trip_service.dart';
import 'package:flutter_application_helpvrywhere/services/user_service.dart';
import 'package:flutter_application_helpvrywhere/widgets/matched_requester_toast.dart';

/// Home-screen banner that surfaces "Help on the way" the instant a
/// helper confirms — no matter which screen the requester is on.
///
/// Subscribes to [TripService.watchActiveForRequester] for the current
/// user and renders the rich [MatchedRequesterToast] for the most-recent
/// active trip. When the trip flips to [TripStatus.atDoor], auto-pushes
/// [ArrivedRequesterScreen] so the requester gets the door-verify
/// challenge without having to navigate manually.
///
/// Renders an empty box when there's no active trip — invisible by
/// default, doesn't push other home content down.
///
/// Drop this at the top of any screen the requester lives on (the
/// "I need help" tab is the primary integration point). Safe to
/// include on multiple screens — the auto-push is guarded against
/// duplicates so the user can't end up with two arrival screens stacked.
class HomeMatchedBanner extends StatefulWidget {
  const HomeMatchedBanner({super.key});

  @override
  State<HomeMatchedBanner> createState() => _HomeMatchedBannerState();
}

class _HomeMatchedBannerState extends State<HomeMatchedBanner> {
  /// Trip ids we've already announced via the auto-push, to dedupe
  /// re-renders of the same atDoor stream emission.
  final Set<String> _announcedAtDoor = <String>{};

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<List<Trip>>(
      stream: TripService().watchActiveForRequester(uid),
      builder: (ctx, snap) {
        final trips = snap.data ?? const <Trip>[];
        if (trips.isEmpty) return const SizedBox.shrink();

        // Most-recent first (sort defensively — stream order isn't
        // guaranteed across all Firestore SDK versions).
        final sorted = [...trips]
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        final trip = sorted.first;

        // If this trip flipped to atDoor and we haven't announced it
        // yet, push the arrival screen on the next frame.
        if (trip.status == TripStatus.atDoor &&
            !_announcedAtDoor.contains(trip.id)) {
          _announcedAtDoor.add(trip.id);
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted) return;
            final helperName = await _resolveName(trip.helperUid);
            if (!mounted) return;
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ArrivedRequesterScreen(
                  trip: trip,
                  helperName: helperName,
                ),
              ),
            );
          });
        }

        // For non-completed trips show the rich toast. Zero outer
        // margin — the home tab's parent column already provides
        // 16 px of horizontal padding; we just want a bottom gap
        // before the next section ("AI support" / "My requests").
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: MatchedRequesterToast(
            trip: trip,
            margin: EdgeInsets.zero,
          ),
        );
      },
    );
  }

  Future<String> _resolveName(String uid) async {
    try {
      final name = await UserService().getUsername(uid);
      if (name.isEmpty || name == 'Unknown') return 'Your helper';
      return name;
    } catch (_) {
      return 'Your helper';
    }
  }
}

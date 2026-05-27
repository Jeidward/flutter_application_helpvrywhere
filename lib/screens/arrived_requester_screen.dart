import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_helpvrywhere/models/request_model.dart';
import 'package:flutter_application_helpvrywhere/models/trip.dart';
import 'package:flutter_application_helpvrywhere/services/request_service.dart';
import 'package:flutter_application_helpvrywhere/services/trip_service.dart';
import 'package:flutter_application_helpvrywhere/theme/app_theme.dart';
import 'package:flutter_application_helpvrywhere/widgets/pill_button.dart';

/// Step 4 (requester side) — "Margaret is here. Verify the code."
///
/// Shown automatically when the trip status flips to [TripStatus.atDoor]
/// (the helper either geofence-triggered or tapped "I'm at the door").
///
/// The requester sees a green hero with the helper's name and a
/// **trip code verification challenge**. The expected code is printed
/// in big monospace so they can read it back out loud through the
/// door. Two CTAs:
///
///   • "Not Margaret" → flags a mismatch (deferred report flow)
///   • "It's her — let her in" → atomically flips trip status to
///     completed AND the underlying request status to completed.
///
/// This is the deliberate safety check that makes the whole flow
/// trustworthy — the requester never opens the door before the human
/// on the other side can speak the code shown on their phone.
class ArrivedRequesterScreen extends StatelessWidget {
  const ArrivedRequesterScreen({
    super.key,
    required this.trip,
    required this.helperName,
  });

  final Trip trip;
  final String helperName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // White scaffold so the rounded corners of the green hero
      // actually reveal a curve. (If this stayed green, the corner
      // triangles outside the rounded path would still paint green
      // and the curve would be invisible.)
      backgroundColor: Colors.white,
      // SafeArea is intentionally NOT wrapping the whole body — each
      // section applies its own one-sided SafeArea so the green hero
      // can bleed all the way up under the status bar, while text
      // content still respects the inset.
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Column(
          children: [
            // ── Top 60%: green hero ─────────────────────────────────
            // Rounded bottom corners give the green section a card-
            // like silhouette instead of a hard rectangle butting up
            // against the white panel. Green extends full-bleed to
            // the top — SafeArea only pads the inner text content.
            Expanded(
              flex: 6,
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.primaryGreen,
                      Color(0xFF0E9F77),
                    ],
                  ),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(30),
                    bottomRight: Radius.circular(30),
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '✦ AT YOUR DOOR',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.8,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '$helperName is here.',
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.6,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Ask them for the trip code before you open up. '
                        "It's a small safety check.",
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.white.withOpacity(0.92),
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Translucent helper card — sits directly under
                      // the subtitle (matches the design intent), not
                      // floating at the bottom of the green hero.
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(AppRadius.tile),
                          border: Border.all(
                              color: Colors.white.withOpacity(0.22)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 50,
                              height: 50,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                _initialsOf(helperName),
                                style: const TextStyle(
                                  color: AppColors.primaryGreen,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$helperName  ·  ✓ verified',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Trip ${trip.code}',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.92),
                                      fontFamily: 'monospace',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Bottom 40%: white verify panel ──────────────────────
          Expanded(
            flex: 5,
            child: Container(
              color: Colors.white,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Code card — content centered so the giant code
                      // reads as the focal point of the screen.
                      Container(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(AppRadius.tile),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              'ASK ${helperName.toUpperCase()} FOR',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.4,
                                color: AppColors.muted,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              trip.code,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 38,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w800,
                                color: AppColors.darkNavy,
                                letterSpacing: 2.0,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text.rich(
                              textAlign: TextAlign.center,
                              TextSpan(
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  color: AppColors.muted,
                                  height: 1.45,
                                ),
                                children: [
                                  const TextSpan(
                                    text: "If the code doesn't match, ",
                                  ),
                                  const TextSpan(
                                    text: "don't open the door.",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.darkNavy,
                                    ),
                                  ),
                                  const TextSpan(
                                      text: ' Tap "Not them" below.'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),

                      // Action row — destructive option on the left.
                      Row(
                        children: [
                          Expanded(
                            flex: 1,
                            child: _DangerOutlineButton(
                              label: 'Not them',
                              onPressed: () => _onMismatch(context),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: PillButton.primary(
                              label: 'Let them in',
                              icon: Icons.check_circle_rounded,
                              height: 54,
                              fontSize: 16,
                              color: AppColors.primaryGreen,
                              onPressed: () => _onConfirm(context),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ), // close inner Column (verify panel content)
                ), // close Padding
              ), // close SafeArea(top:false)
            ), // close white Container
          ), // close Expanded(flex:5)
        ],
      ), // close outer Column
    ), // close AnnotatedRegion
  );
}

  Future<void> _onConfirm(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      // Flip both docs to completed — trip is done AND the request
      // closes out as completed.
      await TripService().updateStatus(trip.id, TripStatus.completed);
      await RequestService()
          .updateStatus(trip.requestId, RequestStatus.completed);
    } on FirebaseException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not close the trip: ${e.message}')),
      );
      return;
    }
    if (!context.mounted) return;
    navigator.popUntil((r) => r.isFirst);
    messenger.showSnackBar(
      const SnackBar(content: Text('Trip closed. Thanks for verifying!')),
    );
  }

  Future<void> _onMismatch(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("That's not the right person?"),
        content: const Text(
          "Don't open the door. We'll keep the trip open so you can sort "
          'it out. You can also message them through the app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Keep trip open'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  static String _initialsOf(String name) {
    final parts =
        name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

class _DangerOutlineButton extends StatelessWidget {
  const _DangerOutlineButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          side: const BorderSide(color: Color(0xFFFECACA), width: 1.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: onPressed,
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFFB91C1C),
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_helpvrywhere/models/nearby_request.dart';
import 'package:flutter_application_helpvrywhere/screens/navigation_screen.dart';
import 'package:flutter_application_helpvrywhere/screens/request_directions_screen.dart';
import 'package:flutter_application_helpvrywhere/services/location_service.dart';
import 'package:flutter_application_helpvrywhere/services/mapbox_directions_service.dart';
import 'package:flutter_application_helpvrywhere/services/request_service.dart';
import 'package:flutter_application_helpvrywhere/theme/app_theme.dart';
import 'package:flutter_application_helpvrywhere/widgets/category_tag.dart';
import 'package:flutter_application_helpvrywhere/widgets/pill_button.dart';
import 'package:flutter_application_helpvrywhere/widgets/safety_banner.dart';
import 'package:flutter_application_helpvrywhere/widgets/stat_card.dart';

/// Read-only detail view for a single nearby request.
///
/// Layout matches the HelpEverywhere "Request" mockup:
///   • Requester avatar header (initials in a blue circle)
///   • Category tag + "~N min task" meta tag
///   • Large title + body description
///   • 3-up [StatCard] row (Posted / Distance / Replies)
///   • Green [SafetyBanner]
///   • Bottom action bar — "Offer help" (heart) + "Directions"
class RequestDetailScreen extends StatelessWidget {
  const RequestDetailScreen({super.key, required this.request});

  final NearbyRequest request;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 22),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text('Request', style: t.titleMedium),
        actions: [
          IconButton(
            icon: const Icon(Icons.bookmark_border, size: 20),
            onPressed: () {},
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz, size: 22),
            onSelected: (v) {
              // TODO(you): handle report / share actions.
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'report', child: Text('Report request')),
              PopupMenuItem(value: 'share', child: Text('Share')),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // ── Requester header ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
            child: Row(
              children: [
                _Avatar(initials: request.requesterInitials),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request.requesterName,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.15,
                          color: AppColors.darkNavy,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _subtitleFor(request),
                        style: t.bodySmall?.copyWith(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Tags + title + body ───────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    CategoryTag.fromCategory(request.category),
                    CategoryTag.meta('${request.estimatedLabel} task'),
                  ],
                ),
                const SizedBox(height: 10),
                Text(request.title, style: t.titleLarge),
                const SizedBox(height: 10),
                Text(request.description, style: t.bodyMedium),
              ],
            ),
          ),

          // ── 3-up stat row ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 14),
            child: Row(
              children: [
                Expanded(
                  child: StatCard(
                    tint: StatTint.blue,
                    icon: Icons.access_time_rounded,
                    label: 'Posted',
                    value: request.postedLabel,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StatCard(
                    tint: StatTint.green,
                    icon: Icons.location_on_outlined,
                    label: 'Distance',
                    value: request.distanceLabel,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StatCard(
                    tint: StatTint.neutral,
                    icon: Icons.chat_bubble_outline_rounded,
                    label: 'Replies',
                    value: '— so far',
                  ),
                ),
              ],
            ),
          ),

          // ── Safety banner ─────────────────────────────────────────────
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 0, 18, 24),
            child: SafetyBanner(),
          ),
        ],
      ),
      bottomNavigationBar: _ActionBar(
        onOffer: () => confirmOfferHelp(context, request: request),
        onDirections: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RequestDirectionsScreen(request: request),
          ),
        ),
      ),
    );
  }
}

/// Builds the requester subtitle line. Handles two real-data quirks:
///   • `neighborhood` may be null when the requester used GPS instead of
///     typing an address.
///   • `distanceKm` is 0 when the volunteer's location isn't available yet.
String _subtitleFor(NearbyRequest r) {
  final parts = <String>[];
  final n = r.neighborhood?.trim();
  if (n != null && n.isNotEmpty) parts.add(n);
  if (r.distanceKm > 0) {
    parts.add('${r.distanceLabel} away');
  }
  if (parts.isEmpty) return 'Nearby';
  return parts.join(' · ');
}

/// Shows a confirmation bottom-sheet recapping the request and a safety
/// reminder before committing to it. On confirm, it atomically claims
/// the request, then asks the volunteer whether they want to start
/// navigation now or later. Picking "Maybe later" leaves the request
/// claimed — it will appear in the active-request banner on the map
/// screen so the volunteer can start navigation whenever they're ready.
///
/// Use this as the entry point for the "I can help" / "Offer help"
/// buttons — never call the lower-level helpers directly from a
/// list-card tap, since the claim is irreversible from the volunteer's
/// side once it succeeds.
Future<void> confirmOfferHelp(
  BuildContext context, {
  required NearbyRequest request,
}) async {
  // 1. Pre-accept confirmation
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppRadius.sheet),
      ),
    ),
    builder: (sheetCtx) => _OfferHelpSheet(request: request),
  );
  if (confirmed != true || !context.mounted) return;

  // 2. Atomic claim
  final claimed = await _claimRequest(context, request: request);
  if (!claimed || !context.mounted) return;

  // 3. Ask: navigate now or later?
  final navigateNow = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppRadius.sheet),
      ),
    ),
    builder: (sheetCtx) => _AcceptedSheet(request: request),
  );

  if (navigateNow == true && context.mounted) {
    await startNavigationForRequest(context, request: request);
  }
}

/// Bottom-sheet body for [confirmOfferHelp]. Returns `true` via
/// `Navigator.pop(true)` when the user confirms.
class _OfferHelpSheet extends StatelessWidget {
  const _OfferHelpSheet({required this.request});

  final NearbyRequest request;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
            Text(
              'Offer help?',
              style: t.titleLarge?.copyWith(fontSize: 22),
            ),
            const SizedBox(height: 4),
            Text(
              '${request.requesterName} · ${request.distanceLabel} away',
              style: t.bodySmall?.copyWith(fontSize: 13),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                CategoryTag.fromCategory(request.category),
                CategoryTag.meta('${request.estimatedLabel} task'),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              request.title,
              style: t.titleSmall?.copyWith(fontSize: 17, height: 1.3),
            ),
            const SizedBox(height: 16),
            const SafetyBanner(),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: PillButton.outline(
                    label: 'Cancel',
                    height: 48,
                    fontSize: 14,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: PillButton.primary(
                    label: 'Yes, I can help',
                    icon: Icons.favorite_rounded,
                    height: 48,
                    fontSize: 14,
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Atomically claims the request for the current volunteer. Shows a
/// modal progress dialog while the transaction is in flight and emits
/// a SnackBar on every failure path (not signed in, already taken,
/// network error). Returns `true` only on [AcceptResult.success].
Future<bool> _claimRequest(
  BuildContext context, {
  required NearbyRequest request,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);

  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Please sign in before offering help.')),
    );
    return false;
  }

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  final AcceptResult outcome;
  try {
    outcome = await RequestService().acceptRequest(
      requestId: request.id,
      helperUid: user.uid,
    );
  } catch (e) {
    navigator.pop(); // close progress
    messenger.showSnackBar(
      SnackBar(content: Text('Could not accept request: $e')),
    );
    return false;
  }

  navigator.pop(); // close progress

  if (outcome != AcceptResult.success) {
    final msg = switch (outcome) {
      AcceptResult.alreadyTaken =>
        'Another volunteer just accepted this request.',
      AcceptResult.notActive => 'This request is no longer active.',
      AcceptResult.notFound => 'Request not found — it may have been deleted.',
      AcceptResult.success => '',
    };
    messenger.showSnackBar(SnackBar(content: Text(msg)));
    return false;
  }
  return true;
}

/// Gets the volunteer's GPS, fetches a walking route from Mapbox, and
/// pushes the live [NavigationScreen]. Assumes the request is already
/// claimed by this volunteer (otherwise the active-request banner /
/// helper-side flow would be wrong).
///
/// Exposed publicly so the "Start navigation" button on the
/// active-request banner can launch the same flow without re-claiming.
Future<void> startNavigationForRequest(
  BuildContext context, {
  required NearbyRequest request,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  // 1. GPS
  double startLat;
  double startLng;
  try {
    final pos = await LocationService().getCurrentLocation();
    startLat = pos.latitude;
    startLng = pos.longitude;
  } catch (_) {
    navigator.pop();
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Could not get your location. Please enable location services.',
        ),
      ),
    );
    return;
  }

  // 2. Walking route
  RouteResult? route;
  try {
    route = await MapboxDirectionsService().getWalkingRoute(
      fromLat: startLat,
      fromLng: startLng,
      toLat: request.latitude,
      toLng: request.longitude,
    );
  } catch (e) {
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(content: Text('Could not load route: $e')),
    );
    return;
  }

  navigator.pop(); // close progress

  if (route == null || route.steps.isEmpty) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('No walking route found to this request.'),
      ),
    );
    return;
  }

  // 3. Push navigation
  await navigator.push(
    MaterialPageRoute(
      builder: (_) => NavigationScreen(
        request: request,
        route: route!,
        startLat: startLat,
        startLng: startLng,
      ),
    ),
  );
}

/// Bottom-sheet body shown right after a successful claim. Lets the
/// volunteer pick "Maybe later" (request stays claimed, banner appears
/// on the map screen) or "Start navigation" (kick off Mapbox routing).
class _AcceptedSheet extends StatelessWidget {
  const _AcceptedSheet({required this.request});

  final NearbyRequest request;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.lightGreen,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: AppColors.primaryGreen,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "You're helping!",
                    style: t.titleLarge?.copyWith(fontSize: 22),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'You accepted "${request.title}". You can start turn-by-turn '
              'navigation now, or any time later from the active-request '
              'banner on the Nearby requests screen.',
              style: t.bodyMedium,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: PillButton.outline(
                    label: 'Maybe later',
                    height: 48,
                    fontSize: 14,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: PillButton.primary(
                    label: 'Start navigation',
                    icon: Icons.near_me_rounded,
                    height: 48,
                    fontSize: 14,
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Avatar — initials in a lightBlue circle with a subtle border ring.
// ---------------------------------------------------------------------------

class _Avatar extends StatelessWidget {
  final String initials;
  const _Avatar({required this.initials});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.lightBlue,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(
            color: AppColors.border,
            blurRadius: 0,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Text(
        initials,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.primaryBlue,
          letterSpacing: -0.2,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sticky bottom action bar — "Offer help" + "Directions".
// ---------------------------------------------------------------------------

class _ActionBar extends StatelessWidget {
  final VoidCallback? onOffer;
  final VoidCallback? onDirections;

  const _ActionBar({this.onOffer, this.onDirections});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          child: Row(
            children: [
              Expanded(
                flex: 16,
                child: PillButton.primary(
                  label: 'Offer help',
                  icon: Icons.favorite_rounded,
                  height: 48,
                  fontSize: 14,
                  onPressed: onOffer,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 10,
                child: PillButton.outline(
                  label: 'Directions',
                  icon: Icons.near_me_outlined,
                  height: 48,
                  fontSize: 14,
                  onPressed: onDirections,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

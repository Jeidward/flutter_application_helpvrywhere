import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_helpvrywhere/models/nearby_request.dart';
import 'package:flutter_application_helpvrywhere/models/request_model.dart';
import 'package:flutter_application_helpvrywhere/models/trip.dart';
import 'package:flutter_application_helpvrywhere/screens/arrived_requester_screen.dart';
import 'package:flutter_application_helpvrywhere/screens/matched_helper_screen.dart';
import 'package:flutter_application_helpvrywhere/screens/navigation_screen.dart';
import 'package:flutter_application_helpvrywhere/screens/request_directions_screen.dart';
import 'package:flutter_application_helpvrywhere/services/location_service.dart';
import 'package:flutter_application_helpvrywhere/services/mapbox_directions_service.dart';
import 'package:flutter_application_helpvrywhere/services/nearby_request_service.dart';
import 'package:flutter_application_helpvrywhere/services/request_service.dart';
import 'package:flutter_application_helpvrywhere/services/trip_service.dart';
import 'package:flutter_application_helpvrywhere/services/user_service.dart';
import 'package:flutter_application_helpvrywhere/services/viewer_presence_service.dart';
import 'package:flutter_application_helpvrywhere/theme/app_theme.dart';
import 'package:flutter_application_helpvrywhere/widgets/category_tag.dart';
import 'package:flutter_application_helpvrywhere/widgets/confirm_help_sheet.dart';
import 'package:flutter_application_helpvrywhere/widgets/matched_requester_toast.dart';
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

  /// Opens the detail screen for a raw [RequestModel] (e.g. the chat
  /// screen's request chips, the "my requests" list, push notifs).
  /// Resolves the requester name + distance via
  /// [NearbyRequestService.fromModel], showing a brief loading dialog,
  /// then pushes the detail route.
  ///
  /// Use this instead of constructing [NearbyRequest] manually — that
  /// would force every caller to re-implement the GPS + user-name
  /// lookups.
  static Future<void> openForModel(
    BuildContext context,
    RequestModel model, {
    NearbyRequestService? service,
  }) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final svc = service ?? NearbyRequestService();
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    NearbyRequest nearby;
    try {
      nearby = await svc.fromModel(model, currentUserId: currentUid);
    } catch (e) {
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('Could not load request: $e')),
      );
      return;
    }

    navigator.pop(); // close loading
    await navigator.push(
      MaterialPageRoute(
        builder: (_) => RequestDetailScreen(request: nearby),
      ),
    );
  }

  /// Opens the detail screen by Firestore doc id only. Use this when
  /// the caller doesn't even have a [RequestModel] in hand — e.g. a
  /// push notification carrying just a request id, or a deep link.
  ///
  /// Surfaces a SnackBar if the doc no longer exists.
  static Future<void> openById(
    BuildContext context,
    String requestId, {
    NearbyRequestService? service,
  }) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final svc = service ?? NearbyRequestService();
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    NearbyRequest nearby;
    try {
      nearby = await svc.fromId(requestId, currentUserId: currentUid);
    } on RequestNotFoundException {
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Request not found — it may have been deleted.'),
        ),
      );
      return;
    } catch (e) {
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('Could not load request: $e')),
      );
      return;
    }

    navigator.pop();
    await navigator.push(
      MaterialPageRoute(
        builder: (_) => RequestDetailScreen(request: nearby),
      ),
    );
  }

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
          // Registers/de-registers this user as an active viewer of
          // the request so the requester's "N neighbours are
          // checking" counter on the home tab stays accurate. Renders
          // nothing — it's a presence side-effect.
          _ViewerPresenceTracker(requestId: request.id),

          // ── Help-on-the-way toast (requester-side, when this is
          // your request and a helper has confirmed) ──────────────────
          _MaybeMatchedToast(request: request),

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
      bottomNavigationBar: _buildActionBar(context),
    );
  }

  /// Picks the right bottom-action bar based on the current user's
  /// relationship to this request. Four mutually-exclusive cases:
  ///
  ///   1. **You posted it** → "Offer help" makes no sense. Show only
  ///      "Directions" (still useful as a sanity-check of the pin).
  ///   2. **You already accepted it** → swap "Offer help" for
  ///      "Start navigation" so the user resumes instead of re-claims.
  ///   3. **Status != active** (cancelled / completed / accepted by
  ///      someone else) → no offer action; show "Directions" only.
  ///   4. **Active, not yours, not yours-accepted** → the default
  ///      "Offer help" + "Directions" pair.
  Widget _buildActionBar(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final status = request.request.status;
    final isMine =
        currentUid != null && request.requesterUserId == currentUid;
    final isMyAccepted = currentUid != null &&
        request.request.helperUserId == currentUid &&
        status == RequestStatus.accepted;
    final canOffer =
        !isMine && !isMyAccepted && status == RequestStatus.active;

    final directions = PillButton.outline(
      label: 'Directions',
      icon: Icons.near_me_outlined,
      height: 48,
      fontSize: 14,
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RequestDirectionsScreen(request: request),
        ),
      ),
    );

    if (isMyAccepted) {
      return _ActionBar(
        primary: PillButton.primary(
          label: 'Start navigation',
          icon: Icons.near_me_rounded,
          height: 48,
          fontSize: 14,
          onPressed: () =>
              startNavigationForRequest(context, request: request),
        ),
        secondary: directions,
      );
    }

    if (canOffer) {
      return _ActionBar(
        primary: PillButton.primary(
          label: 'Offer help',
          icon: Icons.favorite_rounded,
          height: 48,
          fontSize: 14,
          onPressed: () => confirmOfferHelp(context, request: request),
        ),
        secondary: directions,
      );
    }

    // Case 1 (mine) and case 3 (closed) — just Directions.
    return _ActionBar(secondary: directions);
  }
}

/// Renders [MatchedRequesterToast] when the current user is the
/// requester AND a [Trip] exists for this request.
///
/// Also reacts to live status changes:
///   • When the trip flips to [TripStatus.atDoor] (helper geofenced
///     in or tapped "I'm at the door"), this widget auto-pushes
///     [ArrivedRequesterScreen] so the requester immediately sees
///     the trip-code verification challenge — no manual refresh.
///   • When status reaches [TripStatus.completed], the toast hides
///     itself (the trip is done; nothing to surface).
class _MaybeMatchedToast extends StatefulWidget {
  const _MaybeMatchedToast({required this.request});

  final NearbyRequest request;

  @override
  State<_MaybeMatchedToast> createState() => _MaybeMatchedToastState();
}

class _MaybeMatchedToastState extends State<_MaybeMatchedToast> {
  /// Stops the same trip from being announced twice if the stream
  /// re-emits while ArrivedRequesterScreen is already on top.
  String? _announcedAtDoorTripId;

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final isMine =
        currentUid != null && widget.request.requesterUserId == currentUid;
    if (!isMine) return const SizedBox.shrink();

    return StreamBuilder<Trip?>(
      stream: TripService().watchByRequestId(widget.request.id),
      builder: (ctx, snap) {
        // If the Firestore stream errored, log it so the
        // "toast never appears" symptom doesn't stay invisible.
        if (snap.hasError) {
          debugPrint(
            '_MaybeMatchedToast stream error for '
            'request ${widget.request.id}: ${snap.error}',
          );
        }
        final trip = snap.data;
        if (trip == null) return const SizedBox.shrink();
        if (trip.status == TripStatus.completed) {
          return const SizedBox.shrink();
        }

        // Auto-route to the arrival screen the moment the trip flips
        // to atDoor. Guard against duplicate pushes from re-renders.
        if (trip.status == TripStatus.atDoor &&
            _announcedAtDoorTripId != trip.id) {
          _announcedAtDoorTripId = trip.id;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted) return;
            // Look up the helper's display name so the arrival screen
            // can render "Margaret is here." rather than "Helper is here."
            final helperName =
                await _resolveHelperName(trip.helperUid);
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

        return MatchedRequesterToast(trip: trip);
      },
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

/// **Entry point for the "I can help" / "Offer help" buttons.**
///
/// The full Step 1 → Step 2 flow:
///   1. Show the rich [ConfirmHelpSheet] (ETA + distance + AI checklist
///      + free-text note). If the volunteer backs out → nothing happens.
///   2. Atomically claim the request via [RequestService.acceptRequest].
///      If someone else won the race → SnackBar, abort.
///   3. Create the matching [Trip] doc in Firestore with the commitment
///      data — this is the single source of truth both phones will
///      stream from for the rest of the journey.
///   4. Push [MatchedHelperScreen] (the dark-navy "you're linked" hero
///      with the trip code). If the volunteer taps "Start navigation"
///      there, kick off [startNavigationForRequest]. Otherwise the
///      trip stays in `confirmed` status and surfaces in the active-
///      request banner on the map screen for later.
///
/// Never call the lower-level [_claimRequest] / [TripService] /
/// navigation helpers directly from a list-card tap — go through this
/// orchestrator so the volunteer always sees the confirm sheet first.
Future<void> confirmOfferHelp(
  BuildContext context, {
  required NearbyRequest request,
}) async {
  // Step 1 — confirmation sheet
  final commitment = await ConfirmHelpSheet.show(context, request: request);
  if (commitment == null || !context.mounted) return;

  // Step 2 — atomic claim
  final claimed = await _claimRequest(context, request: request);
  if (!claimed || !context.mounted) return;

  // Step 3 — create the trip doc
  final trip = await _createTripForCommitment(
    context,
    request: request,
    commitment: commitment,
  );
  if (trip == null || !context.mounted) return;

  // Resolve helper display name for the matched screen.
  final auth = FirebaseAuth.instance.currentUser!;
  final helperName = await _resolveHelperName(auth.uid);
  if (!context.mounted) return;

  // Step 4 — push the matched screen. Pops with `true` if the user
  // taps "Start navigation"; `null` if they back out.
  final startNav = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => MatchedHelperScreen(
        request: request,
        trip: trip,
        helperInitials: _initialsFromName(helperName),
        helperDisplayName: helperName,
      ),
    ),
  );

  if (startNav == true && context.mounted) {
    await startNavigationForRequest(context, request: request);
  }
}

/// Creates the trip Firestore doc once the request has been claimed.
/// Wraps [TripService.createForAcceptedRequest], surfaces a SnackBar
/// on failure, and returns the freshly-created [Trip] (which carries
/// the deterministic code like "BLU · 47").
Future<Trip?> _createTripForCommitment(
  BuildContext context, {
  required NearbyRequest request,
  required HelpCommitment commitment,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final auth = FirebaseAuth.instance.currentUser!;
  try {
    return await TripService().createForAcceptedRequest(
      requestId: request.id,
      requesterUid: request.requesterUserId,
      helperUid: auth.uid,
      etaMinutes: commitment.etaMinutes,
      distanceKm: request.distanceKm,
      bringList: commitment.items,
      helperNote: commitment.helperNote,
    );
  } on FirebaseException catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Could not start the trip: ${e.message}')),
    );
    return null;
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Could not start the trip: $e')),
    );
    return null;
  }
}

/// Looks up the helper's display name from the `users` collection.
/// Falls back to "You" so the matched-screen never renders a blank
/// avatar.
Future<String> _resolveHelperName(String uid) async {
  try {
    final name = await UserService().getUsername(uid);
    if (name.isEmpty || name == 'Unknown') return 'You';
    return name;
  } catch (_) {
    return 'You';
  }
}

/// "Margaret K." → "MK". Mirrors [NearbyRequest.requesterInitials].
String _initialsFromName(String name) {
  final parts =
      name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts.first[0] + parts.last[0]).toUpperCase();
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
/// claimed by this volunteer.
///
/// When called from a "Help on the way" entry point, also looks up
/// the matching [Trip] doc so the navigation screen can push live
/// helper position to Firestore and trigger the arrival handshake on
/// geofence. The "Directions" pill on the detail screen calls this
/// without a trip — turn-by-turn only, no Firestore sync.
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

  // 3. Look up the active trip for this request (if any). Lets the
  // nav screen sync helper position back to Firestore.
  Trip? trip;
  try {
    trip = await TripService().findByRequestId(request.id);
  } catch (_) {/* not fatal — proceed without trip sync */}

  navigator.pop(); // close progress

  if (route == null || route.steps.isEmpty) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('No walking route found to this request.'),
      ),
    );
    return;
  }

  // 4. Push navigation. Pass the trip so the nav screen can push
  // helper GPS + flip status to enRoute / atDoor.
  await navigator.push(
    MaterialPageRoute(
      builder: (_) => NavigationScreen(
        request: request,
        route: route!,
        startLat: startLat,
        startLng: startLng,
        trip: trip,
      ),
    ),
  );
}

// NOTE: the old `_AcceptedSheet` ("Maybe later" / "Start navigation"
// bottom sheet) lived here. It was replaced by the design-handoff
// [MatchedHelperScreen] — the dark-navy "you're linked" hero with the
// trip code. See `lib/screens/matched_helper_screen.dart`.

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

/// Flexible sticky bottom action bar.
///
///   • If [primary] is provided → renders `[primary] + [secondary]` at
///     16:10 flex (matches the original mockup proportions).
///   • If [primary] is `null` → renders only [secondary], full-width.
///
/// The role-based logic in [RequestDetailScreen._buildActionBar] picks
/// which combination to pass.
class _ActionBar extends StatelessWidget {
  const _ActionBar({this.primary, required this.secondary});

  final Widget? primary;
  final Widget secondary;

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
          child: primary == null
              ? secondary
              : Row(
                  children: [
                    Expanded(flex: 16, child: primary!),
                    const SizedBox(width: 10),
                    Expanded(flex: 10, child: secondary),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Invisible widget that, while mounted, registers the current user
/// as an active viewer of [requestId] via [ViewerPresenceService].
/// Cleans up on dispose. Inserted at the top of the detail screen's
/// `ListView` so its lifecycle matches the screen exactly.
class _ViewerPresenceTracker extends StatefulWidget {
  const _ViewerPresenceTracker({required this.requestId});
  final String requestId;

  @override
  State<_ViewerPresenceTracker> createState() =>
      _ViewerPresenceTrackerState();
}

class _ViewerPresenceTrackerState extends State<_ViewerPresenceTracker> {
  PresenceHandle? _handle;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _handle = ViewerPresenceService().startViewing(
      requestId: widget.requestId,
      viewerUid: uid,
    );
  }

  @override
  void dispose() {
    _handle?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

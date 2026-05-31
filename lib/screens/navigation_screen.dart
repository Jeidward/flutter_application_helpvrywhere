import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_helpvrywhere/models/nearby_request.dart';
import 'package:flutter_application_helpvrywhere/models/trip.dart';
import 'package:flutter_application_helpvrywhere/screens/arrived_helper_screen.dart';
import 'package:flutter_application_helpvrywhere/services/mapbox_directions_service.dart';
import 'package:flutter_application_helpvrywhere/services/trip_service.dart';
import 'package:flutter_application_helpvrywhere/widgets/map_markers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

/// Google-Maps-style in-app navigation.
///
///   • Subscribes to the live Geolocator position stream (5-meter filter).
///   • Camera follows the user (pitch + bearing matching heading).
///   • Big top banner: arrow icon for next turn + instruction + distance
///     to the next maneuver.
///   • TTS announces each step the moment we transition to it.
///   • Bottom bar: total remaining distance + ETA + an End button.
///   • When the volunteer is within 30 m of the destination we show
///     "You've arrived" and stop the position stream.
///
/// Expects to be passed a fully-routed [RouteResult] so it doesn't have
/// to re-query Mapbox Directions on its own.
class NavigationScreen extends StatefulWidget {
  const NavigationScreen({
    super.key,
    required this.request,
    required this.route,
    required this.startLat,
    required this.startLng,
    this.trip,
  });

  final NearbyRequest request;
  final RouteResult route;
  final double startLat;
  final double startLng;

  /// When supplied, this screen acts as the "live trip" stage of the
  /// "Help on the way" flow. It will:
  ///   • Flip the trip status to [TripStatus.enRoute] on open
  ///   • Push helper GPS to the trip doc every ~10 s (so the
  ///     requester's tracking screen shows movement)
  ///   • On geofence hit (50 m), push to [ArrivedHelperScreen]
  ///     (which then flips status to [TripStatus.atDoor]).
  ///
  /// Pass `null` for the legacy "directions only" mode used by the
  /// "Directions" pill on the request detail screen — no trip
  /// updates, just turn-by-turn.
  final Trip? trip;

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  final FlutterTts _tts = FlutterTts();

  // Live position
  StreamSubscription<Position>? _posSub;
  Position? _currentPos;
  double _currentBearing = 0.0;

  // Step tracking
  int _currentStepIdx = 0;
  bool _arrived = false;

  // Map handles
  mb.MapboxMap? _map;
  mb.PointAnnotationManager? _pointMgr;
  mb.PolylineAnnotationManager? _lineMgr;
  mb.PointAnnotation? _userMarker;

  // Trip syncing (helper-side). When [widget.trip] is non-null we push
  // GPS to Firestore every 10 s so the requester's tracking screen
  // sees movement, and we route to ArrivedHelperScreen on geofence.
  DateTime _lastTripPush = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _tripPushInterval = Duration(seconds: 10);

  @override
  void initState() {
    super.initState();
    _initTts();
    _startLocationStream();
    _markTripEnRouteIfNeeded();
    // Announce the very first step as soon as the screen opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.route.steps.isNotEmpty) {
        _speak(widget.route.steps[0].instruction);
      }
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _tts.stop();
    super.dispose();
  }

  // ── TTS ──────────────────────────────────────────────────────────────

  Future<void> _initTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  Future<void> _speak(String text) async {
    if (text.trim().isEmpty) return;
    await _tts.stop();
    await _tts.speak(text);
  }

  // ── Position stream ──────────────────────────────────────────────────

  void _startLocationStream() {
    const settings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5,
    );
    _posSub =
        Geolocator.getPositionStream(locationSettings: settings).listen(
      (pos) {
        if (!mounted) return;
        setState(() {
          _currentPos = pos;
          if (pos.heading >= 0) _currentBearing = pos.heading;
        });
        _onPositionUpdated(pos);
      },
      onError: (_) {
        // Stream can error out e.g. when permission is revoked mid-trip;
        // we just stop updating and keep the last known frame on screen.
      },
    );
  }

  void _onPositionUpdated(Position pos) {
    _updateUserPin(pos);
    _followCamera(pos);
    _advanceStepsIfNeeded(pos);
    _pushTripLocationIfDue(pos);
    _checkArrival(pos);
  }

  /// Flips the trip to `enRoute` on screen open. Best-effort — if the
  /// write fails, the requester just sees the trip stay in
  /// `confirmed`; the next location push will retry.
  Future<void> _markTripEnRouteIfNeeded() async {
    final trip = widget.trip;
    if (trip == null) return;
    if (trip.status == TripStatus.enRoute ||
        trip.status == TripStatus.atDoor ||
        trip.status == TripStatus.completed) {
      return;
    }
    try {
      await TripService().updateStatus(trip.id, TripStatus.enRoute);
    } catch (_) {/* surfaced on the next push */}
  }

  /// Pushes the helper's GPS to the trip doc on a throttled timer so
  /// the requester's tracking screen renders smooth movement without
  /// hammering Firestore. ~10 s cadence; one small doc update per push.
  Future<void> _pushTripLocationIfDue(Position pos) async {
    final trip = widget.trip;
    if (trip == null) return;
    final now = DateTime.now();
    if (now.difference(_lastTripPush) < _tripPushInterval) return;
    _lastTripPush = now;

    // Re-estimate ETA from the remaining route distance. Walking pace
    // assumption matches NearbyRequestService.
    final remainingM = _distanceToDestination();
    final etaMin = (remainingM / 1000 * 12).round().clamp(1, 999);

    try {
      await TripService().updateHelperLocation(
        trip.id,
        lat: pos.latitude,
        lng: pos.longitude,
        etaMinutes: etaMin,
      );
    } catch (_) {/* will retry next interval */}
  }

  Future<void> _updateUserPin(Position pos) async {
    final mgr = _pointMgr;
    if (mgr == null) return;
    if (_userMarker == null) {
      final bytes = await buildUserAvatarMarker(initials: 'YOU');
      _userMarker = await mgr.create(
        mb.PointAnnotationOptions(
          geometry: mb.Point(
            coordinates: mb.Position(pos.longitude, pos.latitude),
          ),
          image: bytes,
          iconSize: 0.55,
        ),
      );
    } else {
      _userMarker!.geometry = mb.Point(
        coordinates: mb.Position(pos.longitude, pos.latitude),
      );
      try {
        await mgr.update(_userMarker!);
      } catch (_) {
        // If update fails (rare), the pin keeps its last position — not
        // worth crashing the trip over.
      }
    }
  }

  Future<void> _followCamera(Position pos) async {
    final map = _map;
    if (map == null) return;
    await map.easeTo(
      mb.CameraOptions(
        center: mb.Point(
          coordinates: mb.Position(pos.longitude, pos.latitude),
        ),
        zoom: 17.0,
        pitch: 50.0,
        bearing: _currentBearing,
      ),
      mb.MapAnimationOptions(duration: 600),
    );
  }

  /// When the user gets close to the NEXT maneuver point, advance the
  /// current step and announce the next instruction.
  void _advanceStepsIfNeeded(Position pos) {
    final steps = widget.route.steps;
    if (_currentStepIdx >= steps.length - 1) return;

    final nextStep = steps[_currentStepIdx + 1];
    final distanceToNext = Geolocator.distanceBetween(
      pos.latitude,
      pos.longitude,
      nextStep.maneuverLat,
      nextStep.maneuverLng,
    );

    // Threshold: 25 m. Walking speed ~5 km/h ≈ 1.4 m/s, so we get ~15 s
    // of preparation between when we announce the turn and when the user
    // physically reaches it.
    if (distanceToNext < 25) {
      setState(() => _currentStepIdx++);
      _speak(nextStep.instruction);
    }
  }

  void _checkArrival(Position pos) {
    if (_arrived) return;
    final distMeters = Geolocator.distanceBetween(
      pos.latitude,
      pos.longitude,
      widget.request.latitude,
      widget.request.longitude,
    );
    // 50 m geofence matches the design handoff. The legacy "directions
    // only" mode (no trip) keeps the older 30 m threshold so we don't
    // change its UX. Trip mode triggers the arrival screen.
    final trip = widget.trip;
    final threshold = trip == null ? 30 : 50;
    if (distMeters < threshold) {
      setState(() => _arrived = true);
      _speak('You have arrived at the meeting point.');
      _posSub?.cancel();

      if (trip != null) {
        // Route to the calm "You've arrived" screen, which flips the
        // trip to atDoor and signals the requester to verify the code.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => ArrivedHelperScreen(
                trip: trip,
                requesterName: widget.request.requesterName,
                doorLabel: widget.request.requesterLocation,
              ),
            ),
          );
        });
      }
    }
  }

  double _distanceToNextManeuver() {
    final pos = _currentPos;
    if (pos == null) return 0;
    final steps = widget.route.steps;
    if (_currentStepIdx >= steps.length - 1) return 0;
    final next = steps[_currentStepIdx + 1];
    return Geolocator.distanceBetween(
      pos.latitude,
      pos.longitude,
      next.maneuverLat,
      next.maneuverLng,
    );
  }

  double _distanceToDestination() {
    final pos = _currentPos;
    if (pos == null) return widget.route.totalDistanceMeters;
    return Geolocator.distanceBetween(
      pos.latitude,
      pos.longitude,
      widget.request.latitude,
      widget.request.longitude,
    );
  }

  // ── Map setup ────────────────────────────────────────────────────────

  Future<void> _onMapCreated(mb.MapboxMap map) async {
    _map = map;
    _pointMgr = await map.annotations.createPointAnnotationManager();
    _lineMgr = await map.annotations.createPolylineAnnotationManager();

    // Route polyline
    await _lineMgr!.create(
      mb.PolylineAnnotationOptions(
        geometry: mb.LineString(
          coordinates: [
            for (final c in widget.route.geometryLngLat)
              mb.Position(c[0], c[1]),
          ],
        ),
        lineColor: 0xFF4A90E2,
        lineWidth: 6.0,
        lineOpacity: 0.95,
      ),
    );

    // Destination pin
    final destBytes = await buildDestinationMarker();
    await _pointMgr!.create(
      mb.PointAnnotationOptions(
        geometry: mb.Point(
          coordinates: mb.Position(
            widget.request.longitude,
            widget.request.latitude,
          ),
        ),
        image: destBytes,
        iconSize: 0.55,
      ),
    );

    // Initial user pin at the starting point
    if (_currentPos == null) {
      final bytes = await buildUserAvatarMarker(initials: 'YOU');
      _userMarker = await _pointMgr!.create(
        mb.PointAnnotationOptions(
          geometry: mb.Point(
            coordinates: mb.Position(widget.startLng, widget.startLat),
          ),
          image: bytes,
          iconSize: 0.55,
        ),
      );
    }

    // Initial camera frame: pick a zoom that shows the whole route. For
    // a long walk (e.g. 6 km) we need a wide view; for a 100-m walk we
    // can zoom in tight. This avoids the "map looks blank" feeling when
    // we'd otherwise start at zoom 17 with no nearby labels visible.
    final initialZoom = _zoomForDistance(widget.route.totalDistanceMeters);
    final centerLat = (widget.startLat + widget.request.latitude) / 2;
    final centerLng = (widget.startLng + widget.request.longitude) / 2;
    await map.flyTo(
      mb.CameraOptions(
        center: mb.Point(
          coordinates: mb.Position(centerLng, centerLat),
        ),
        zoom: initialZoom,
        pitch: 0.0,
        bearing: 0,
      ),
      mb.MapAnimationOptions(duration: 700),
    );
  }

  /// Heuristic for the initial camera zoom: shows more of the route on
  /// long walks, zooms in tight on short ones.
  double _zoomForDistance(double meters) {
    if (meters < 200) return 17.0;
    if (meters < 500) return 16.0;
    if (meters < 1000) return 15.5;
    if (meters < 2000) return 14.5;
    if (meters < 5000) return 13.5;
    return 12.5;
  }

  // ── UI ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final step = widget.route.steps.isNotEmpty
        ? widget.route.steps[_currentStepIdx]
        : null;
    final nextStep = (_currentStepIdx < widget.route.steps.length - 1)
        ? widget.route.steps[_currentStepIdx + 1]
        : null;
    final distToNext = _distanceToNextManeuver();
    final distToDest = _distanceToDestination();
    final etaMin = (distToDest / 1000 * 12).round().clamp(1, 999);

    return Scaffold(
      backgroundColor: const Color(0xFFEFF1F4),
      // StackFit.expand forces the Stack to fill the Scaffold body, no
      // matter what the children's intrinsic sizes are. Without it, the
      // Stack can collapse to the height of its smallest child, which
      // makes Positioned(bottom: ...) land partway up the screen.
      body: Stack(
        fit: StackFit.expand,
        children: [
          mb.MapWidget(
            cameraOptions: mb.CameraOptions(
              center: mb.Point(
                coordinates: mb.Position(widget.startLng, widget.startLat),
              ),
              // Wider initial zoom so the user can see the route shape
              // before we tighten in for turn-by-turn navigation.
              zoom: 14.0,
              pitch: 0.0,
            ),
            styleUri: mb.MapboxStyles.LIGHT,
            onMapCreated: _onMapCreated,
          ),

          // ── Top banner: current / next step ──────────────────────────
          // Explicitly Positioned at top so the layout doesn't depend on
          // Stack default alignment.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: _StepBanner(
                  arrived: _arrived,
                  stepInstruction:
                      nextStep?.instruction ?? step?.instruction ?? '',
                  distanceToNext: distToNext,
                  maneuverType:
                      nextStep?.maneuverType ?? step?.maneuverType ?? '',
                  maneuverModifier: nextStep?.maneuverModifier ??
                      step?.maneuverModifier ??
                      '',
                  onExit: () => Navigator.pop(context),
                ),
              ),
            ),
          ),

          // ── Bottom card: ETA / remaining / End ───────────────────────
          Positioned(
            left: 12,
            right: 12,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _BottomBar(
                  arrived: _arrived,
                  remainingMeters: distToDest,
                  etaMinutes: etaMin,
                  destinationTitle: widget.request.title,
                  onEnd: () => Navigator.pop(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Top banner ─────────────────────────────────────────────────────────

class _StepBanner extends StatelessWidget {
  const _StepBanner({
    required this.arrived,
    required this.stepInstruction,
    required this.distanceToNext,
    required this.maneuverType,
    required this.maneuverModifier,
    required this.onExit,
  });

  final bool arrived;
  final String stepInstruction;
  final double distanceToNext;
  final String maneuverType;
  final String maneuverModifier;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    if (arrived) {
      return _bannerShell(
        bg: const Color(0xFF1F9D55),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 36),
            const SizedBox(width: 14),
            const Expanded(
              child: Text(
                "You've arrived at the meeting point",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: onExit,
            ),
          ],
        ),
      );
    }

    final icon = _iconForManeuver(maneuverType, maneuverModifier);
    return _bannerShell(
      bg: const Color(0xFF1F2937),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF4A90E2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  distanceToNext > 0
                      ? 'In ${_formatDistance(distanceToNext)}'
                      : 'Now',
                  style: const TextStyle(
                    color: Color(0xFFA5B4FC),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  stepInstruction,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bannerShell({required Color bg, required Widget child}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

// ─── Bottom bar ─────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.arrived,
    required this.remainingMeters,
    required this.etaMinutes,
    required this.destinationTitle,
    required this.onEnd,
  });

  final bool arrived;
  final double remainingMeters;
  final int etaMinutes;
  final String destinationTitle;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  destinationTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  arrived
                      ? 'Arrived'
                      : '${_formatDistance(remainingMeters)} · ~$etaMinutes min',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: onEnd,
            icon: const Icon(Icons.close, size: 18),
            label: Text(arrived ? 'Done' : 'End'),
            style: FilledButton.styleFrom(
              backgroundColor:
                  arrived ? const Color(0xFF1F9D55) : const Color(0xFFC2453A),
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Helpers ────────────────────────────────────────────────────────────

IconData _iconForManeuver(String type, String modifier) {
  switch (type) {
    case 'depart':
      return Icons.directions_walk;
    case 'arrive':
      return Icons.flag;
    case 'turn':
      switch (modifier) {
        case 'left':
          return Icons.turn_left;
        case 'slight left':
          return Icons.turn_slight_left;
        case 'sharp left':
          return Icons.turn_sharp_left;
        case 'right':
          return Icons.turn_right;
        case 'slight right':
          return Icons.turn_slight_right;
        case 'sharp right':
          return Icons.turn_sharp_right;
        case 'uturn':
          return Icons.u_turn_left;
        default:
          return Icons.turn_right;
      }
    case 'continue':
    case 'new name':
    case 'use lane':
      return Icons.straight;
    case 'merge':
      return Icons.merge;
    case 'roundabout':
    case 'rotary':
    case 'exit roundabout':
    case 'exit rotary':
      return modifier == 'left'
          ? Icons.roundabout_left
          : Icons.roundabout_right;
    case 'fork':
      return modifier.contains('left') ? Icons.fork_left : Icons.fork_right;
    case 'end of road':
      return modifier == 'left' ? Icons.turn_left : Icons.turn_right;
    default:
      return Icons.arrow_forward;
  }
}

String _formatDistance(double meters) {
  if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)} km';
  if (meters >= 50) return '${(meters / 10).round() * 10} m';
  return '${meters.round()} m';
}

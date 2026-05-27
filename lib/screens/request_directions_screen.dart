import 'package:flutter/material.dart';
import 'package:flutter_application_helpvrywhere/models/nearby_request.dart';
import 'package:flutter_application_helpvrywhere/services/location_service.dart';
import 'package:flutter_application_helpvrywhere/services/mapbox_directions_service.dart';
import 'package:flutter_application_helpvrywhere/widgets/map_markers.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

/// Directions view: full-screen Mapbox map with the **real walking route**
/// between the volunteer (avatar pin) and the request meeting point
/// (destination pin), plus a draggable bottom sheet listing the
/// turn-by-turn steps that come back from the Mapbox Directions API.
class RequestDirectionsScreen extends StatefulWidget {
  const RequestDirectionsScreen({super.key, required this.request});

  final NearbyRequest request;

  @override
  State<RequestDirectionsScreen> createState() =>
      _RequestDirectionsScreenState();
}

class _RequestDirectionsScreenState extends State<RequestDirectionsScreen> {
  final MapboxDirectionsService _directions = MapboxDirectionsService();

  // Used only as a last resort if the user has location turned off so
  // the map can still render something centered roughly on the service
  // area. Matches the default used elsewhere in the project (Suwon).
  static const double _fallbackLat = 37.2843;
  static const double _fallbackLng = 127.0463;
  static const String _currentUserName = 'You';

  Position? _userPosition;
  RouteResult? _route;
  bool _loadingRoute = true;
  String? _routeError;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /// Reads the volunteer's GPS, then asks Mapbox for a walking route to
  /// the request's coordinates. Either step is best-effort — if GPS is
  /// unavailable we fall back to a fixed origin; if Mapbox fails we
  /// surface the error in the bottom sheet but still draw the pins.
  Future<void> _bootstrap() async {
    Position? pos;
    try {
      pos = await LocationService().getCurrentLocation();
    } catch (_) {
      // Permission denied or location services off — fallback origin.
    }

    final fromLat = pos?.latitude ?? _fallbackLat;
    final fromLng = pos?.longitude ?? _fallbackLng;

    try {
      final result = await _directions.getWalkingRoute(
        fromLat: fromLat,
        fromLng: fromLng,
        toLat: widget.request.latitude,
        toLng: widget.request.longitude,
      );
      if (!mounted) return;
      setState(() {
        _userPosition = pos;
        _route = result;
        _loadingRoute = false;
        if (result == null) {
          _routeError = 'No walking route found to this location.';
        }
      });
    } on DirectionsException catch (e) {
      if (!mounted) return;
      setState(() {
        _userPosition = pos;
        _loadingRoute = false;
        _routeError = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _userPosition = pos;
        _loadingRoute = false;
        _routeError = 'Unexpected error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final userLat = _userPosition?.latitude ?? _fallbackLat;
    final userLng = _userPosition?.longitude ?? _fallbackLng;

    final totalMinutes = _route != null
        ? (_route!.totalDurationSeconds / 60).round().clamp(1, 999)
        : (widget.request.distanceKm * 12).round().clamp(1, 999);
    final totalKm = _route != null
        ? _route!.totalDistanceMeters / 1000.0
        : widget.request.distanceKm;

    return Scaffold(
      backgroundColor: const Color(0xFFEFF1F4),
      body: Stack(
        children: [
          Positioned.fill(
            child: _DirectionsMap(
              userLat: userLat,
              userLng: userLng,
              userName: _currentUserName,
              destLat: widget.request.latitude,
              destLng: widget.request.longitude,
              routeGeometry: _route?.geometryLngLat,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  _RoundIconButton(
                    icon: Icons.arrow_back,
                    onTap: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  _RoundIconButton(
                    icon: Icons.layers_outlined,
                    onTap: () {
                      // TODO(you): toggle map style (satellite/transit).
                    },
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 280,
            child: _RoundIconButton(
              icon: Icons.my_location,
              onTap: () {
                // TODO(you): recenter map on user.
              },
            ),
          ),
          DraggableScrollableSheet(
            initialChildSize: 0.42,
            minChildSize: 0.18,
            maxChildSize: 0.85,
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x1F000000),
                      blurRadius: 20,
                      offset: Offset(0, -4),
                    ),
                  ],
                ),
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.zero,
                  children: [
                    const SizedBox(height: 8),
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD1D5DB),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _RouteSummary(
                        title: widget.request.title,
                        subtitle:
                            '${widget.request.requesterName}  ·  '
                            '${totalKm.toStringAsFixed(1)} km  ·  '
                            '~$totalMinutes min walk',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF4A90E2),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () {
                                // TODO(you): launch external maps with
                                // destination = request lat/lng.
                              },
                              icon: const Icon(Icons.navigation, size: 18),
                              label: const Text(
                                'Open in Maps',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Divider(height: 1, color: Color(0xFFEFF1F4)),
                    const SizedBox(height: 8),
                    // ── Step list / loading / error ─────────────────────
                    _buildStepsContent(),
                    const SizedBox(height: 24),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStepsContent() {
    if (_loadingRoute) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Column(
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              SizedBox(height: 12),
              Text(
                'Loading walking directions…',
                style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
              ),
            ],
          ),
        ),
      );
    }

    if (_routeError != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, size: 20, color: Color(0xFFB45309)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _routeError!,
                style: const TextStyle(fontSize: 13, color: Color(0xFF92400E)),
              ),
            ),
          ],
        ),
      );
    }

    final steps = _route?.steps ?? const [];
    if (steps.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        child: Text(
          'No steps to show.',
          style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
        ),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          _StepTile(
            step: steps[i],
            index: i + 1,
            isLast: i == steps.length - 1,
          ),
      ],
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Mapbox map with two pins + the routed polyline.
// ───────────────────────────────────────────────────────────────────────────

class _DirectionsMap extends StatefulWidget {
  const _DirectionsMap({
    required this.userLat,
    required this.userLng,
    required this.userName,
    required this.destLat,
    required this.destLng,
    required this.routeGeometry,
  });

  final double userLat;
  final double userLng;
  final String userName;
  final double destLat;
  final double destLng;

  /// List of [lng, lat] pairs from Mapbox Directions. Null while the
  /// route is still loading — we draw a temporary straight line in that
  /// case so the map isn't empty.
  final List<List<double>>? routeGeometry;

  @override
  State<_DirectionsMap> createState() => _DirectionsMapState();
}

class _DirectionsMapState extends State<_DirectionsMap> {
  mb.MapboxMap? _map;
  mb.PointAnnotationManager? _pointMgr;
  mb.PolylineAnnotationManager? _lineMgr;
  mb.PolylineAnnotation? _currentLine;

  Future<void> _onMapCreated(mb.MapboxMap map) async {
    _map = map;
    _pointMgr = await map.annotations.createPointAnnotationManager();
    _lineMgr = await map.annotations.createPolylineAnnotationManager();

    await _drawRouteLine();

    // User avatar pin.
    final userBytes = await buildUserAvatarMarker(
      initials: initialsFromName(widget.userName),
    );
    await _pointMgr!.create(
      mb.PointAnnotationOptions(
        geometry: mb.Point(
          coordinates: mb.Position(widget.userLng, widget.userLat),
        ),
        image: userBytes,
        iconSize: 0.5,
      ),
    );

    // Destination pin.
    final destBytes = await buildDestinationMarker();
    await _pointMgr!.create(
      mb.PointAnnotationOptions(
        geometry: mb.Point(
          coordinates: mb.Position(widget.destLng, widget.destLat),
        ),
        image: destBytes,
        iconSize: 0.5,
      ),
    );

    // Frame the camera on the midpoint between user and destination.
    final centerLat = (widget.userLat + widget.destLat) / 2;
    final centerLng = (widget.userLng + widget.destLng) / 2;
    await _map!.flyTo(
      mb.CameraOptions(
        center: mb.Point(coordinates: mb.Position(centerLng, centerLat)),
        zoom: 14.5,
      ),
      mb.MapAnimationOptions(duration: 500),
    );
  }

  @override
  void didUpdateWidget(_DirectionsMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The routed geometry arrives ~half a second after the map appears
    // (HTTP round-trip to Mapbox). Redraw the polyline when it lands.
    if (oldWidget.routeGeometry != widget.routeGeometry && _lineMgr != null) {
      _drawRouteLine();
    }
  }

  /// Draws either the routed polyline (when available) or a temporary
  /// straight line between the two pins so the map isn't empty.
  Future<void> _drawRouteLine() async {
    final mgr = _lineMgr;
    if (mgr == null) return;

    // Remove the previous line first.
    if (_currentLine != null) {
      try {
        await mgr.delete(_currentLine!);
      } catch (_) {}
      _currentLine = null;
    }

    final List<mb.Position> coords;
    final geometry = widget.routeGeometry;
    if (geometry != null && geometry.length >= 2) {
      coords = [for (final c in geometry) mb.Position(c[0], c[1])];
    } else {
      // Loading / error — show a faint straight line as a placeholder.
      coords = [
        mb.Position(widget.userLng, widget.userLat),
        mb.Position(widget.destLng, widget.destLat),
      ];
    }

    _currentLine = await mgr.create(
      mb.PolylineAnnotationOptions(
        geometry: mb.LineString(coordinates: coords),
        lineColor: 0xFF4A90E2,
        lineWidth: 4.0,
        lineOpacity: geometry != null ? 0.95 : 0.45,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return mb.MapWidget(
      cameraOptions: mb.CameraOptions(
        center: mb.Point(
          coordinates: mb.Position(widget.userLng, widget.userLat),
        ),
        zoom: 13.5,
      ),
      styleUri: mb.MapboxStyles.LIGHT,
      onMapCreated: _onMapCreated,
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Bottom-sheet pieces
// ───────────────────────────────────────────────────────────────────────────

class _RouteSummary extends StatelessWidget {
  const _RouteSummary({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 13.5, color: Color(0xFF6B7280)),
        ),
      ],
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.step,
    required this.index,
    required this.isLast,
  });

  final RouteStep step;
  final int index;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final icon = _iconForManeuver(step.maneuverType, step.maneuverModifier);
    final detail = _formatDistance(step.distanceMeters);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF4FA),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFD9E4F1)),
                ),
                child: Icon(icon, size: 16, color: const Color(0xFF4A90E2)),
              ),
              if (!isLast)
                Container(
                  width: 2,
                  height: 24,
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  color: const Color(0xFFE3E6EB),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.instruction,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827),
                    ),
                  ),
                  if (detail.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Maps Mapbox `maneuver.type` + `modifier` to a Material directional
/// icon. Falls back to a generic arrow for any rare maneuvers we don't
/// special-case.
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
  if (meters >= 50) return '${(meters / 10).round() * 10} m'; // round to 10
  return '${meters.round()} m';
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 20, color: const Color(0xFF1F2937)),
        ),
      ),
    );
  }
}

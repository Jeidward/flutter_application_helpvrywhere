import 'package:flutter/material.dart';
import 'package:flutter_application_helpvrywhere/models/nearby_request.dart';
import 'package:flutter_application_helpvrywhere/widgets/map_markers.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

/// Directions view: full-screen Mapbox map with the route between the
/// volunteer (avatar pin) and the request meeting point (destination
/// pin), plus a draggable bottom sheet for turn-by-turn steps.
///
/// The polyline drawn here is just a straight line between the two
/// points — swap it for a real routed polyline (Mapbox Directions API)
/// when you wire that up.
class RequestDirectionsScreen extends StatelessWidget {
  const RequestDirectionsScreen({super.key, required this.request});

  final NearbyRequest request;

  // TODO(you): replace with the volunteer's actual position from
  // LocationService and their display name.
  static const double _userLat = 37.2843;
  static const double _userLng = 127.0463;
  static const String _currentUserName = 'You';

  // TODO(you): replace with real route steps from Mapbox Directions API.
  static const _mockSteps = <_DirectionStep>[
    _DirectionStep(
      icon: Icons.straight,
      instruction: 'Head north on Bongnyeong-ro',
      detail: '180 m',
    ),
    _DirectionStep(
      icon: Icons.turn_right,
      instruction: 'Turn right onto Yeongtong-daero',
      detail: '320 m',
    ),
    _DirectionStep(
      icon: Icons.turn_left,
      instruction: 'Turn left at the second crosswalk',
      detail: '90 m',
    ),
    _DirectionStep(
      icon: Icons.flag,
      instruction: 'Arrive at meeting point',
      detail: '',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final estimatedWalkMin = (request.distanceKm * 12).round().clamp(1, 120);

    return Scaffold(
      backgroundColor: const Color(0xFFEFF1F4),
      body: Stack(
        children: [
          Positioned.fill(
            child: _DirectionsMap(
              userLat: _userLat,
              userLng: _userLng,
              userName: _currentUserName,
              destLat: request.latitude,
              destLng: request.longitude,
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
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(24)),
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
                        title: request.title,
                        subtitle:
                            '${request.requesterName} · ${request.distanceKm.toStringAsFixed(1)} km · ~$estimatedWalkMin min walk',
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
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF1F2937),
                              side: const BorderSide(color: Color(0xFFD1D5DB)),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () {
                              // TODO(you): open in-app chat with requester.
                            },
                            icon: const Icon(
                              Icons.chat_bubble_outline,
                              size: 18,
                            ),
                            label: const Text(
                              'Chat',
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Divider(height: 1, color: Color(0xFFEFF1F4)),
                    const SizedBox(height: 8),
                    for (var i = 0; i < _mockSteps.length; i++)
                      _StepTile(
                        step: _mockSteps[i],
                        index: i + 1,
                        isLast: i == _mockSteps.length - 1,
                      ),
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
}

class _DirectionsMap extends StatefulWidget {
  const _DirectionsMap({
    required this.userLat,
    required this.userLng,
    required this.userName,
    required this.destLat,
    required this.destLng,
  });

  final double userLat;
  final double userLng;
  final String userName;
  final double destLat;
  final double destLng;

  @override
  State<_DirectionsMap> createState() => _DirectionsMapState();
}

class _DirectionsMapState extends State<_DirectionsMap> {
  mb.MapboxMap? _map;
  mb.PointAnnotationManager? _pointMgr;
  mb.PolylineAnnotationManager? _lineMgr;

  Future<void> _onMapCreated(mb.MapboxMap map) async {
    _map = map;
    _pointMgr = await map.annotations.createPointAnnotationManager();
    _lineMgr = await map.annotations.createPolylineAnnotationManager();

    await _lineMgr!.create(
      mb.PolylineAnnotationOptions(
        geometry: mb.LineString(
          coordinates: [
            mb.Position(widget.userLng, widget.userLat),
            mb.Position(widget.destLng, widget.destLat),
          ],
        ),
        lineColor: 0xFF4A90E2,
        lineWidth: 4.0,
        lineOpacity: 0.9,
      ),
    );

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

class _DirectionStep {
  const _DirectionStep({
    required this.icon,
    required this.instruction,
    required this.detail,
  });

  final IconData icon;
  final String instruction;
  final String detail;
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.step,
    required this.index,
    required this.isLast,
  });

  final _DirectionStep step;
  final int index;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
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
                child: Icon(
                  step.icon,
                  size: 16,
                  color: const Color(0xFF4A90E2),
                ),
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
                  if (step.detail.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      step.detail,
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

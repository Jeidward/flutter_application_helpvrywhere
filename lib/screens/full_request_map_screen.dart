import 'package:flutter/material.dart';
import 'package:flutter_application_helpvrywhere/models/nearby_request.dart';
import 'package:flutter_application_helpvrywhere/screens/request_detail_screen.dart';
import 'package:flutter_application_helpvrywhere/widgets/map_markers.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

/// Fullscreen Mapbox map showing every nearby request (numbered orange
/// pin) plus the volunteer's current position (avatar pin), with a
/// draggable bottom sheet listing the same requests as compact cards.
///
/// Data is passed in from [RequestMapScreen] — this screen does NOT
/// re-query Firestore. Keeps the two views in sync (same filter applied)
/// and avoids extra reads.
class FullRequestMapScreen extends StatefulWidget {
  const FullRequestMapScreen({
    super.key,
    required this.userLat,
    required this.userLng,
    required this.userName,
    required this.requests,
  });

  final double? userLat;
  final double? userLng;
  final String userName;
  final List<NearbyRequest> requests;

  static const double _fallbackLat = 37.2843;
  static const double _fallbackLng = 127.0463;

  @override
  State<FullRequestMapScreen> createState() => _FullRequestMapScreenState();
}

class _FullRequestMapScreenState extends State<FullRequestMapScreen> {
  mb.MapboxMap? _map;
  mb.PointAnnotationManager? _manager;

  Future<void> _onMapCreated(mb.MapboxMap map) async {
    _map = map;
    _manager = await map.annotations.createPointAnnotationManager();
    await _refreshMarkers();
    await _frameCamera();
  }

  Future<void> _refreshMarkers() async {
    final manager = _manager;
    if (manager == null) return;
    await manager.deleteAll();

    if (widget.userLat != null && widget.userLng != null) {
      final userBytes = await buildUserAvatarMarker(
        initials: initialsFromName(widget.userName),
      );
      await manager.create(
        mb.PointAnnotationOptions(
          geometry: mb.Point(
            coordinates: mb.Position(widget.userLng!, widget.userLat!),
          ),
          image: userBytes,
          iconSize: 0.55,
        ),
      );
    }

    for (var i = 0; i < widget.requests.length; i++) {
      final r = widget.requests[i];
      final bytes = await buildNumberedRequestMarker(number: i + 1);
      await manager.create(
        mb.PointAnnotationOptions(
          geometry:
              mb.Point(coordinates: mb.Position(r.longitude, r.latitude)),
          image: bytes,
          iconSize: 0.55,
        ),
      );
    }
  }

  /// Centers on the centroid of all visible points (user + requests).
  /// Good enough for the capstone scope; replace with a proper bounding-
  /// box fit later if you want all pins visible at any zoom.
  Future<void> _frameCamera() async {
    final lats = <double>[];
    final lngs = <double>[];
    if (widget.userLat != null && widget.userLng != null) {
      lats.add(widget.userLat!);
      lngs.add(widget.userLng!);
    }
    for (final r in widget.requests) {
      lats.add(r.latitude);
      lngs.add(r.longitude);
    }
    if (lats.isEmpty) return;
    final centerLat = lats.reduce((a, b) => a + b) / lats.length;
    final centerLng = lngs.reduce((a, b) => a + b) / lngs.length;
    await _map?.flyTo(
      mb.CameraOptions(
        center: mb.Point(coordinates: mb.Position(centerLng, centerLat)),
        zoom: 13.5,
      ),
      mb.MapAnimationOptions(duration: 500),
    );
  }

  Future<void> _recenterOnUser() async {
    final lat = widget.userLat;
    final lng = widget.userLng;
    if (lat == null || lng == null) {
      await _frameCamera();
      return;
    }
    await _map?.flyTo(
      mb.CameraOptions(
        center: mb.Point(coordinates: mb.Position(lng, lat)),
        zoom: 15.0,
      ),
      mb.MapAnimationOptions(duration: 500),
    );
  }

  @override
  Widget build(BuildContext context) {
    final initialLat = widget.userLat ??
        (widget.requests.isNotEmpty
            ? widget.requests.first.latitude
            : FullRequestMapScreen._fallbackLat);
    final initialLng = widget.userLng ??
        (widget.requests.isNotEmpty
            ? widget.requests.first.longitude
            : FullRequestMapScreen._fallbackLng);

    return Scaffold(
      backgroundColor: const Color(0xFFEFF1F4),
      body: Stack(
        children: [
          Positioned.fill(
            child: mb.MapWidget(
              cameraOptions: mb.CameraOptions(
                center: mb.Point(
                  coordinates: mb.Position(initialLng, initialLat),
                ),
                zoom: 13.5,
              ),
              styleUri: mb.MapboxStyles.LIGHT,
              onMapCreated: _onMapCreated,
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
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.location_on,
                            size: 18,
                            color: Color(0xFF4A90E2),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${widget.requests.length} nearby '
                            'request${widget.requests.length == 1 ? '' : 's'}',
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1F2937),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 240,
            child: _RoundIconButton(
              icon: Icons.my_location,
              onTap: _recenterOnUser,
            ),
          ),
          DraggableScrollableSheet(
            initialChildSize: 0.32,
            minChildSize: 0.12,
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
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: widget.requests.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, idx) {
                    if (idx == 0) {
                      return Column(
                        children: [
                          Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFD1D5DB),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              widget.requests.isEmpty
                                  ? 'No active requests'
                                  : 'Tap a request to see details',
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                          ),
                        ],
                      );
                    }
                    final r = widget.requests[idx - 1];
                    return _MapListTile(
                      number: idx,
                      request: r,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RequestDetailScreen(request: r),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MapListTile extends StatelessWidget {
  const _MapListTile({
    required this.number,
    required this.request,
    required this.onTap,
  });

  final int number;
  final NearbyRequest request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasDistance = request.distanceKm > 0;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE3E6EB)),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Color(0xFFD2502A),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$number',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasDistance
                          ? '${request.requesterName} · '
                              '${request.distanceKm.toStringAsFixed(1)} km'
                          : request.requesterName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: Color(0xFF9CA3AF),
                size: 22,
              ),
            ],
          ),
        ),
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

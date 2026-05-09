import 'package:flutter/material.dart';
import 'package:flutter_application_helpvrywhere/models/nearby_request.dart';
import 'package:flutter_application_helpvrywhere/models/request_model.dart';
import 'package:flutter_application_helpvrywhere/screens/full_request_map_screen.dart';
import 'package:flutter_application_helpvrywhere/screens/request_detail_screen.dart';
import 'package:flutter_application_helpvrywhere/screens/request_directions_screen.dart';
import 'package:flutter_application_helpvrywhere/services/auth_service.dart';
import 'package:flutter_application_helpvrywhere/services/location_service.dart';
import 'package:flutter_application_helpvrywhere/services/request_service.dart';
import 'package:flutter_application_helpvrywhere/widgets/map_markers.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

/// Volunteer-facing screen that shows real Firestore requests near the user.
///
/// Live wiring:
///   • `RequestService.getRequests()` streams every request in the project.
///     We filter to `status == active` on the client. The volunteer's own
///     requests are INCLUDED so single-account testing works — flip the
///     `r.userId == _myUid` check in `_toNearby` to exclude them in
///     production if you'd rather not show self-authored requests.
///   • `LocationService.getCurrentLocation()` gives the volunteer's
///     position so we can compute distance per request and recenter
///     the map.
///   • `AuthService.getUserDocument(uid)` resolves each request's
///     `userId` → `UserModel.username` so the card shows a real name.
///     Results cached for the session.
class RequestMapScreen extends StatefulWidget {
  const RequestMapScreen({super.key});

  @override
  State<RequestMapScreen> createState() => _RequestMapScreenState();
}

class _RequestMapScreenState extends State<RequestMapScreen> {
  final RequestService _requestService = RequestService();
  final AuthService _authService = AuthService();

  // Visual filter — applied client-side over the same Firestore stream.
  RequestCategory? _activeCategory;

  // Volunteer identity & live position.
  String? _myUid;
  String _myUsername = 'You';
  Position? _myPosition;
  bool _locationDenied = false;

  // userId → resolved username. Seeded with '' while a fetch is in
  // flight so we don't kick off duplicate Firestore reads.
  final Map<String, String> _userNameCache = {};

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /// Loads volunteer identity + GPS. Both are best-effort — failures
  /// just degrade the UI (no "You" pin, no per-request distances) but
  /// don't block the screen.
  Future<void> _bootstrap() async {
    final user = _authService.currentUser;
    if (user != null) {
      _myUid = user.uid;
      try {
        final doc = await _authService.getUserDocument(user.uid);
        if (doc != null && mounted) {
          setState(() => _myUsername = doc.username);
        }
      } catch (_) {}
    }

    try {
      final pos = await LocationService().getCurrentLocation();
      if (mounted) {
        setState(() {
          _myPosition = pos;
          _locationDenied = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _locationDenied = true);
    }
  }

  /// Lazily fetches a username for a userId. Caches the result so we
  /// only hit Firestore once per author per session.
  void _ensureUserNameLoaded(String userId) {
    if (_userNameCache.containsKey(userId)) return;
    _userNameCache[userId] = '';
    _authService.getUserDocument(userId).then((doc) {
      if (!mounted) return;
      if (doc != null) {
        setState(() => _userNameCache[userId] = doc.username);
      }
    }).catchError((_) {});
  }

  /// Transforms raw Firestore docs into the presentation [NearbyRequest]
  /// view-models. Filters out non-active requests + the inactive
  /// category. Sorts by distance ascending.
  List<NearbyRequest> _toNearby(List<RequestModel> raw) {
    final myLat = _myPosition?.latitude;
    final myLng = _myPosition?.longitude;

    final filtered = raw.where((r) {
      if (r.status != RequestStatus.active) return false;
      if (_activeCategory != null &&
          RequestCategoryX.fromRaw(r.category) != _activeCategory) {
        return false;
      }
      return true;
    }).toList();

    final list = filtered.map((r) {
      final isMine = _myUid != null && r.userId == _myUid;
      if (!isMine) _ensureUserNameLoaded(r.userId);

      double distance = 0;
      if (myLat != null && myLng != null) {
        distance = Geolocator.distanceBetween(
              myLat,
              myLng,
              r.latitude,
              r.longitude,
            ) /
            1000.0;
      }
      // Walking estimate: ~5 km/h → 12 min/km. Clamp for sanity.
      final minutes = (distance * 12).round().clamp(1, 999);

      final String displayName;
      if (isMine) {
        displayName = 'You';
      } else {
        final cached = _userNameCache[r.userId] ?? '';
        displayName = cached.isNotEmpty ? cached : 'Requester';
      }

      return NearbyRequest(
        request: r,
        requesterName: displayName,
        distanceKm: distance,
        estimatedMinutes: minutes,
      );
    }).toList()
      ..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        title: const Text(
          'Nearby requests',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh location',
            onPressed: _bootstrap,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _bootstrap();
        },
        child: StreamBuilder<List<RequestModel>>(
          stream: _requestService.getRequests(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Could not load requests:\n${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            final raw = snapshot.data ?? [];
            final nearby = _toNearby(raw);

            return ListView(
              padding: EdgeInsets.zero,
              children: [
                _MapPreview(
                  userLat: _myPosition?.latitude,
                  userLng: _myPosition?.longitude,
                  userName: _myUsername,
                  requests: nearby,
                  onOpenFullMap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FullRequestMapScreen(
                        userLat: _myPosition?.latitude,
                        userLng: _myPosition?.longitude,
                        userName: _myUsername,
                        requests: nearby,
                      ),
                    ),
                  ),
                ),
                if (_locationDenied) const _LocationDeniedBanner(),
                _CategoryFilterBar(
                  activeCategory: _activeCategory,
                  onChanged: (c) => setState(() => _activeCategory = c),
                ),
                if (nearby.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: _EmptyState(),
                  )
                else
                  for (var i = 0; i < nearby.length; i++)
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        i == 0 ? 4 : 0,
                        16,
                        i == nearby.length - 1 ? 24 : 12,
                      ),
                      child: _RequestCard(
                        request: nearby[i],
                        colorScheme: theme.colorScheme,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                RequestDetailScreen(request: nearby[i]),
                          ),
                        ),
                        onHelp: () {
                          // TODO(you): replace SnackBar with your real
                          // accept-request flow.
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'You offered help for "${nearby[i].title}"',
                              ),
                            ),
                          );
                        },
                        onDirections: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                RequestDirectionsScreen(request: nearby[i]),
                          ),
                        ),
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Banner shown when location permission was denied.
// ---------------------------------------------------------------------------

class _LocationDeniedBanner extends StatelessWidget {
  const _LocationDeniedBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFCE7B5)),
      ),
      child: Row(
        children: const [
          Icon(Icons.location_off, color: Color(0xFFB45309), size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Location is off — distances and the "You" pin are unavailable. '
              'Pull to refresh after enabling location.',
              style: TextStyle(fontSize: 13, color: Color(0xFF92400E)),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Map preview — real Mapbox map with user avatar pin + numbered request pins
// ---------------------------------------------------------------------------

class _MapPreview extends StatefulWidget {
  const _MapPreview({
    required this.userLat,
    required this.userLng,
    required this.userName,
    required this.requests,
    required this.onOpenFullMap,
  });

  final double? userLat;
  final double? userLng;
  final String userName;
  final List<NearbyRequest> requests;
  final VoidCallback onOpenFullMap;

  static const double _fallbackLat = 37.2843;
  static const double _fallbackLng = 127.0463;

  @override
  State<_MapPreview> createState() => _MapPreviewState();
}

class _MapPreviewState extends State<_MapPreview> {
  mb.MapboxMap? _map;
  mb.PointAnnotationManager? _manager;

  String _lastSignature = '';

  @override
  void didUpdateWidget(_MapPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sig = _signature();
    if (sig != _lastSignature && _manager != null) {
      _refreshMarkers();
    }
  }

  String _signature() {
    final ids = widget.requests.map((r) => r.id).join(',');
    return '${widget.userLat}|${widget.userLng}|${widget.userName}|$ids';
  }

  Future<void> _onMapCreated(mb.MapboxMap map) async {
    _map = map;
    _manager = await map.annotations.createPointAnnotationManager();
    await _refreshMarkers();
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
          iconSize: 0.5,
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
          iconSize: 0.5,
        ),
      );
    }

    _lastSignature = _signature();
  }

  Future<void> _recenter() async {
    final lat = widget.userLat ?? _MapPreview._fallbackLat;
    final lng = widget.userLng ?? _MapPreview._fallbackLng;
    await _map?.flyTo(
      mb.CameraOptions(
        center: mb.Point(coordinates: mb.Position(lng, lat)),
        zoom: 14.5,
      ),
      mb.MapAnimationOptions(duration: 600),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lat = widget.userLat ??
        (widget.requests.isNotEmpty
            ? widget.requests.first.latitude
            : _MapPreview._fallbackLat);
    final lng = widget.userLng ??
        (widget.requests.isNotEmpty
            ? widget.requests.first.longitude
            : _MapPreview._fallbackLng);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      height: 220,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE3E6EB)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          mb.MapWidget(
            cameraOptions: mb.CameraOptions(
              center: mb.Point(coordinates: mb.Position(lng, lat)),
              zoom: 14.0,
            ),
            styleUri: mb.MapboxStyles.LIGHT,
            onMapCreated: _onMapCreated,
          ),
          Positioned(
            left: 12,
            top: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.95),
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                '${widget.requests.length} nearby',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1F2937),
                ),
              ),
            ),
          ),
          Positioned(
            right: 12,
            top: 12,
            child: Material(
              color: Colors.white,
              elevation: 2,
              borderRadius: BorderRadius.circular(999),
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: widget.onOpenFullMap,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.fullscreen,
                        size: 16,
                        color: Color(0xFF4A90E2),
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Full map',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF4A90E2),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 12,
            bottom: 12,
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(),
              elevation: 2,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _recenter,
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(
                    Icons.my_location,
                    size: 20,
                    color: Color(0xFF4A90E2),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Category filter bar
// ---------------------------------------------------------------------------

class _CategoryFilterBar extends StatelessWidget {
  const _CategoryFilterBar({
    required this.activeCategory,
    required this.onChanged,
  });

  final RequestCategory? activeCategory;
  final ValueChanged<RequestCategory?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _FilterChip(
              label: 'All',
              selected: activeCategory == null,
              onTap: () => onChanged(null),
            ),
            const SizedBox(width: 8),
            for (final c in RequestCategory.values) ...[
              _FilterChip(
                label: c.label,
                selected: activeCategory == c,
                onTap: () => onChanged(c),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Colors.black : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(
          color: selected ? Colors.black : const Color(0xFFE3E6EB),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : const Color(0xFF1F2937),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Request card
// ---------------------------------------------------------------------------

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.colorScheme,
    required this.onTap,
    required this.onHelp,
    required this.onDirections,
  });

  final NearbyRequest request;
  final ColorScheme colorScheme;
  final VoidCallback onTap;
  final VoidCallback onHelp;
  final VoidCallback onDirections;

  @override
  Widget build(BuildContext context) {
    final hasDistance = request.distanceKm > 0;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE3E6EB)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFFD2502A),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      request.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    _timeAgo(request.postedAt),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text(
                  hasDistance
                      ? '${request.requesterName} · ${request.distanceKm.toStringAsFixed(1)} km'
                      : request.requesterName,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: Color(0xFF4B5563),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _CategoryPill(category: request.category),
                  const SizedBox(width: 8),
                  if (hasDistance)
                    _MetaPill(
                      icon: Icons.schedule,
                      label: '~${request.estimatedMinutes} min',
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF4A90E2),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onPressed: onHelp,
                      child: const Text('I can help'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF1F2937),
                        side: const BorderSide(color: Color(0xFFD1D5DB)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: onDirections,
                      icon: const Icon(Icons.directions, size: 18),
                      label: const Text('Directions'),
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

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({required this.category});

  final RequestCategory category;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF1EC),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        category.label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Color(0xFFB14322),
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F3F5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: const Color(0xFF4B5563)),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF374151),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.inbox_outlined, size: 48, color: Color(0xFF9CA3AF)),
          SizedBox(height: 12),
          Text(
            'No active requests right now',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF374151),
            ),
          ),
          SizedBox(height: 4),
          Text(
            'When other users post a request, it will show up here.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, color: Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _timeAgo(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  return '${diff.inDays} d ago';
}

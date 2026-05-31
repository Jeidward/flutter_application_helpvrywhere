import 'package:flutter/material.dart';
import 'package:flutter_application_helpvrywhere/debug/seed_test_requests.dart';
import 'package:flutter_application_helpvrywhere/models/nearby_request.dart';
import 'package:flutter_application_helpvrywhere/models/request_model.dart';
import 'package:flutter_application_helpvrywhere/screens/full_request_map_screen.dart';
import 'package:flutter_application_helpvrywhere/screens/request_detail_screen.dart';
import 'package:flutter_application_helpvrywhere/screens/request_directions_screen.dart';
import 'package:flutter_application_helpvrywhere/services/auth_service.dart';
import 'package:flutter_application_helpvrywhere/services/location_service.dart';
import 'package:flutter_application_helpvrywhere/services/request_service.dart';
import 'package:flutter_application_helpvrywhere/theme/app_theme.dart';
import 'package:flutter_application_helpvrywhere/widgets/map_markers.dart';
import 'package:flutter_application_helpvrywhere/widgets/pill_button.dart';
import 'package:flutter_application_helpvrywhere/widgets/request_card.dart';
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

  /// Counts per [RequestCategory] over the currently-active raw set
  /// (i.e. status == active, but NOT yet filtered by category). The
  /// `null` key holds the "All" total. Used to render count badges on
  /// the filter chips.
  Map<RequestCategory?, int> _categoryCounts(List<RequestModel> raw) {
    final actives = raw.where((r) => r.status == RequestStatus.active).toList();
    final counts = <RequestCategory?, int>{null: actives.length};
    for (final c in RequestCategory.values) {
      counts[c] = actives
          .where((r) => RequestCategoryX.fromRaw(r.category) == c)
          .length;
    }
    return counts;
  }

  // NOTE: `_wrap` + `_myAccepted` (which fed the old "You're helping X"
  // banner) were removed along with the banner. The helper's active
  // trip now lives on the home tab as `YourActiveTripCard`, driven by
  // `TripService.watchActiveForHelper`.

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
          // ── TEMP: seed 4 test requests near SKKU Natural Sciences
          // Campus so the directions screen has interesting routes.
          // Remove this button (and the import) when you're done seeding.
          IconButton(
            tooltip: 'Seed SKKU test data',
            icon: const Icon(Icons.bug_report),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                await seedTestRequestsNearSKKU();
                if (!mounted) return;
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Seeded 4 requests near SKKU'),
                  ),
                );
              } catch (e) {
                if (!mounted) return;
                messenger.showSnackBar(
                  SnackBar(content: Text('Seed failed: $e')),
                );
              }
            },
          ),
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
            final counts = _categoryCounts(raw);
            // NOTE: the "You're helping X" banner used to render here
            // (`_ActiveRequestBanner`). It's been moved to the home tab
            // as a dedicated card so this screen stays focused on
            // browsing nearby requests. See `your_active_trip_card.dart`.

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
                _CategoryChips(
                  active: _activeCategory,
                  counts: counts,
                  onChange: (c) => setState(() => _activeCategory = c),
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
                      child: RequestCard(
                        request: nearby[i],
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                RequestDetailScreen(request: nearby[i]),
                          ),
                        ),
                        onOffer: () => confirmOfferHelp(
                          context,
                          request: nearby[i],
                        ),
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

  /// Bumps the map zoom by [delta] (positive = zoom in). Reads the
  /// current camera state first so the animation starts from where the
  /// user is actually looking, then clamps to Mapbox's safe range.
  Future<void> _zoomBy(double delta) async {
    final map = _map;
    if (map == null) return;
    try {
      final state = await map.getCameraState();
      final next = (state.zoom + delta).clamp(0.0, 22.0);
      await map.easeTo(
        mb.CameraOptions(zoom: next),
        mb.MapAnimationOptions(duration: 250),
      );
    } catch (_) {
      // Best-effort — silently ignore if the camera isn't ready yet.
    }
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
            child: _NearbyChip(count: widget.requests.length),
          ),
          Positioned(
            right: 12,
            top: 12,
            child: Material(
              color: AppColors.darkNavy,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                onTap: widget.onOpenFullMap,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.open_in_full_rounded,
                          size: 12, color: Colors.white),
                      SizedBox(width: 6),
                      Text(
                        'Full map',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Zoom in / out — stacked vertically on the right, mid-height.
          Positioned(
            right: 12,
            top: 56,
            child: Column(
              children: [
                _MapIconButton(
                  icon: Icons.add,
                  onTap: () => _zoomBy(1),
                ),
                const SizedBox(height: 8),
                _MapIconButton(
                  icon: Icons.remove,
                  onTap: () => _zoomBy(-1),
                ),
              ],
            ),
          ),
          Positioned(
            right: 12,
            bottom: 12,
            child: _MapIconButton(
              icon: Icons.my_location,
              onTap: _recenter,
            ),
          ),
        ],
      ),
    );
  }
}

// NOTE: the inline `_ActiveRequestBanner` ("You're helping X") that
// used to live here has been replaced by a dedicated `YourActiveTripCard`
// on the home tab. Removing it kept the map screen focused purely on
// browsing nearby requests.

// ---------------------------------------------------------------------------
// Small circular icon button used for map overlay actions
// (zoom in / zoom out / recenter).
// ---------------------------------------------------------------------------

class _MapIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _MapIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(side: BorderSide(color: AppColors.border)),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 18, color: AppColors.primaryBlue),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pulse-dot "nearby" chip used on top-left of the map preview.
// ---------------------------------------------------------------------------

class _NearbyChip extends StatefulWidget {
  final int count;
  const _NearbyChip({required this.count});

  @override
  State<_NearbyChip> createState() => _NearbyChipState();
}

class _NearbyChipState extends State<_NearbyChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _ctrl,
            builder: (ctx, _) {
              final t = _ctrl.value;
              final scale = 1.0 + 3.0 * t;
              final opacity = (1.0 - t).clamp(0.0, 1.0) * 0.4;
              return SizedBox(
                width: 8,
                height: 8,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    Transform.scale(
                      scale: scale,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primaryBlue.withOpacity(opacity),
                        ),
                      ),
                    ),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primaryBlue,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(width: 6),
          Text(
            '${widget.count} nearby',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.darkNavy,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Category filter chips — count badge inside each pill.
// ---------------------------------------------------------------------------

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({
    required this.active,
    required this.counts,
    required this.onChange,
  });

  final RequestCategory? active;
  final Map<RequestCategory?, int> counts;
  final ValueChanged<RequestCategory?> onChange;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        children: [
          _Chip(
            label: 'All',
            count: counts[null] ?? 0,
            active: active == null,
            onTap: () => onChange(null),
          ),
          for (final c in RequestCategory.values) ...[
            const SizedBox(width: 10),
            _Chip(
              label: c.label,
              count: counts[c] ?? 0,
              active: active == c,
              onTap: () => onChange(c),
            ),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Active state uses the brand primaryBlue (NOT black) — keeps the
    // selected filter feeling like part of the blue button family.
    final fg = active ? Colors.white : AppColors.darkNavy;
    final bg = active ? AppColors.primaryBlue : Colors.white;
    final countBg =
        active ? Colors.white.withOpacity(0.22) : const Color(0xFFF5F6F8);
    final countFg = active ? Colors.white : AppColors.muted;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: active ? AppColors.primaryBlue : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: countBg,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: countFg,
                  ),
                ),
              ),
            ],
          ),
        ),
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


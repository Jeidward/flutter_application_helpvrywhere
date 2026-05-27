import 'package:flutter_application_helpvrywhere/models/nearby_request.dart';
import 'package:flutter_application_helpvrywhere/models/request_model.dart';
import 'package:flutter_application_helpvrywhere/services/location_service.dart';
import 'package:flutter_application_helpvrywhere/services/request_service.dart';
import 'package:flutter_application_helpvrywhere/services/user_service.dart';
import 'package:geolocator/geolocator.dart';

/// Single source of truth for turning a raw Firestore [RequestModel]
/// into a presentation-layer [NearbyRequest] view-model.
///
/// Centralises the three lookups every "I need a NearbyRequest" caller
/// would otherwise have to re-implement by hand:
///   • requester display name (from the `users` collection)
///   • distance from the current device (via Geolocator)
///   • walking-time estimate (~5 km/h, 12 min/km)
///
/// **When to use this:**
///   • Chat screen → tap a request chip → open the request detail.
///   • Push notification → deep-link to a request.
///   • "My active request" banner → re-open the request from any screen.
///   • Anywhere outside the nearby-feed list that needs to render a
///     request the same way the feed does.
///
/// **When NOT to use this:**
///   • Inside the nearby-feed list itself, which already has the
///     volunteer's GPS in memory and batches name lookups across many
///     requests. That code path lives in [RequestMapScreen] and is
///     intentionally hand-rolled for perf.
class NearbyRequestService {
  NearbyRequestService({
    RequestService? requestService,
    UserService? userService,
    LocationService? locationService,
  })  : _requestService = requestService ?? RequestService(),
        _userService = userService ?? UserService(),
        _locationService = locationService ?? LocationService();

  final RequestService _requestService;
  final UserService _userService;
  final LocationService _locationService;

  // Walking pace assumption — must match RequestMapScreen so the
  // estimated-time labels stay consistent across screens.
  static const double _walkingMinutesPerKm = 12.0;

  /// Wraps a [RequestModel] in a [NearbyRequest], filling in the three
  /// computed fields. Network calls (user name lookup, GPS) are
  /// best-effort — failures degrade gracefully:
  ///   • Unknown user → "Requester"
  ///   • No GPS → distance = 0, label = "—"
  ///
  /// Pass [userPosition] when the caller already has a fresh position
  /// (avoids a redundant Geolocator call). If omitted, the service
  /// tries to fetch GPS itself.
  ///
  /// Pass [currentUserId] so the service can label requests the user
  /// posted themselves as "You" instead of looking up their name.
  Future<NearbyRequest> fromModel(
    RequestModel model, {
    Position? userPosition,
    String? currentUserId,
  }) async {
    final position = userPosition ?? await _safeGetCurrentPosition();
    final requesterName = await _resolveDisplayName(
      model.userId,
      currentUserId: currentUserId,
    );

    final distance = _kmBetween(position, model);
    final minutes = _estimateMinutes(distance);

    return NearbyRequest(
      request: model,
      requesterName: requesterName,
      distanceKm: distance,
      estimatedMinutes: minutes,
    );
  }

  /// One-shot: fetch a request by id and wrap it. Throws
  /// [RequestNotFoundException] if the doc no longer exists.
  Future<NearbyRequest> fromId(
    String requestId, {
    Position? userPosition,
    String? currentUserId,
  }) async {
    final model = await _requestService.getRequestById(requestId);
    if (model == null) {
      throw RequestNotFoundException(requestId);
    }
    return fromModel(
      model,
      userPosition: userPosition,
      currentUserId: currentUserId,
    );
  }

  /// Live stream: emits a fresh [NearbyRequest] every time the
  /// underlying Firestore doc changes. The user name + GPS are looked
  /// up once on the first emission and re-used for subsequent updates
  /// (otherwise we'd hammer Geolocator on every status flip). Emits
  /// `null` when the doc is deleted.
  ///
  /// Useful for screens that should react to live status changes —
  /// e.g. the chat-side "View request" chip updating its colour when
  /// the request moves from `active` → `accepted` → `completed`.
  Stream<NearbyRequest?> watch(
    String requestId, {
    String? currentUserId,
  }) async* {
    Position? position;
    String? cachedName;

    await for (final model in _requestService.watchRequestById(requestId)) {
      if (model == null) {
        yield null;
        continue;
      }

      position ??= await _safeGetCurrentPosition();
      cachedName ??= await _resolveDisplayName(
        model.userId,
        currentUserId: currentUserId,
      );

      final distance = _kmBetween(position, model);
      yield NearbyRequest(
        request: model,
        requesterName: cachedName,
        distanceKm: distance,
        estimatedMinutes: _estimateMinutes(distance),
      );
    }
  }

  /// Wraps a batch of [RequestModel]s in [NearbyRequest]s reusing a
  /// single GPS read and a cache of user-name lookups. Use this in the
  /// chat screen / my-requests screen so listing N requests does ONE
  /// Geolocator call and at most N distinct name lookups.
  Future<List<NearbyRequest>> fromModels(
    List<RequestModel> models, {
    Position? userPosition,
    String? currentUserId,
  }) async {
    if (models.isEmpty) return const [];

    final position = userPosition ?? await _safeGetCurrentPosition();

    // Batch the unique requester-uid lookups.
    final uniqueUids = models.map((m) => m.userId).toSet();
    final nameCache = <String, String>{};
    for (final uid in uniqueUids) {
      nameCache[uid] = await _resolveDisplayName(
        uid,
        currentUserId: currentUserId,
      );
    }

    return models.map((m) {
      final distance = _kmBetween(position, m);
      return NearbyRequest(
        request: m,
        requesterName: nameCache[m.userId] ?? 'Requester',
        distanceKm: distance,
        estimatedMinutes: _estimateMinutes(distance),
      );
    }).toList();
  }

  // ── internals ──────────────────────────────────────────────────────

  /// Reads GPS, swallowing every failure (permissions, services off,
  /// emulator with no fix). Callers that want hard errors should use
  /// [LocationService.getCurrentLocation] directly.
  Future<Position?> _safeGetCurrentPosition() async {
    try {
      return await _locationService.getCurrentLocation();
    } catch (_) {
      return null;
    }
  }

  /// "You" when the request is the caller's own, otherwise the
  /// username from the `users` collection, falling back to "Requester"
  /// if the lookup fails.
  Future<String> _resolveDisplayName(
    String userId, {
    String? currentUserId,
  }) async {
    if (currentUserId != null && userId == currentUserId) return 'You';
    try {
      final name = await _userService.getUsername(userId);
      // UserService returns the literal string "Unknown" on miss —
      // remap to a friendlier label.
      return (name.isEmpty || name == 'Unknown') ? 'Requester' : name;
    } catch (_) {
      return 'Requester';
    }
  }

  double _kmBetween(Position? me, RequestModel target) {
    if (me == null) return 0;
    return Geolocator.distanceBetween(
          me.latitude,
          me.longitude,
          target.latitude,
          target.longitude,
        ) /
        1000.0;
  }

  int _estimateMinutes(double km) =>
      (km * _walkingMinutesPerKm).round().clamp(1, 999);
}

/// Thrown by [NearbyRequestService.fromId] when the Firestore doc for
/// the given id doesn't exist. Lets callers show a "request was
/// deleted" message instead of a generic crash.
class RequestNotFoundException implements Exception {
  RequestNotFoundException(this.requestId);
  final String requestId;

  @override
  String toString() => 'Request "$requestId" not found.';
}

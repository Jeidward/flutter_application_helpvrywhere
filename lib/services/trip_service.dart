import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_application_helpvrywhere/models/trip.dart';
import 'package:flutter_application_helpvrywhere/services/trip_code_generator.dart';

/// CRUD + live streams for the `trips/{id}` collection.
///
/// A trip is created the moment a helper confirms in the step-1 sheet
/// (`createForAcceptedRequest`) and ticks through [TripStatus] as both
/// sides progress through the flow.
///
/// Both phones subscribe to the same doc via [watch] — every UI on
/// the helper or requester side is just a render of the latest [Trip].
///
/// **Lifecycle:**
///   1. `createForAcceptedRequest()` is called from the confirm sheet.
///      Atomically writes a new doc with status `confirmed`.
///   2. Helper taps "Start navigation" → `updateStatus(enRoute)`.
///   3. While en route, the helper's phone pushes GPS via
///      `updateHelperLocation()` every ~10s for the requester's
///      tracking screen.
///   4. Geofence (50m around requester) → `updateStatus(atDoor)`.
///   5. Requester taps "It's her — let her in" →
///      `updateStatus(completed)`.
class TripService {
  TripService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;
  static const String collection = 'trips';

  CollectionReference<Map<String, dynamic>> get _trips =>
      _db.collection(collection);

  // ── Creation ─────────────────────────────────────────────────────────

  /// Creates the trip doc right after a successful
  /// `RequestService.acceptRequest()`. The trip's [Trip.code] is
  /// derived deterministically from the new doc id so both phones can
  /// recompute it locally for offline UI fallbacks.
  ///
  /// Pre-condition: the caller already won the atomic claim on the
  /// request (otherwise you'd be creating a trip for someone else's
  /// accept). This service does NOT re-validate that — keep the call
  /// order: `acceptRequest` first, then `createForAcceptedRequest`.
  Future<Trip> createForAcceptedRequest({
    required String requestId,
    required String requesterUid,
    required String helperUid,
    required int etaMinutes,
    required double distanceKm,
    required List<BringItem> bringList,
    required String helperNote,
  }) async {
    final ref = _trips.doc();
    final code = TripCodeGenerator.fromSeed(ref.id);
    final now = DateTime.now();

    final trip = Trip(
      id: ref.id,
      code: code,
      requestId: requestId,
      helperUid: helperUid,
      requesterUid: requesterUid,
      etaMinutes: etaMinutes,
      distanceKm: distanceKm,
      bringList: bringList,
      helperNote: helperNote,
      status: TripStatus.confirmed,
      createdAt: now,
      updatedAt: now,
    );

    await ref.set(trip.toCreateMap());
    return trip;
  }

  // ── Reads ────────────────────────────────────────────────────────────

  /// One-shot fetch by trip id. Returns null if the doc was deleted
  /// (e.g. by a Cloud Function after step 5 wrap-up).
  Future<Trip?> get(String tripId) async {
    final snap = await _trips.doc(tripId).get();
    if (!snap.exists) return null;
    return Trip.fromMap(snap.data()!, snap.id);
  }

  /// Live stream of a single trip. The primary subscription every
  /// step-2/3/4 screen uses — the screen re-renders whenever
  /// [TripStatus], `etaMinutes`, helper position, or any field changes.
  /// Emits null when the doc is deleted.
  Stream<Trip?> watch(String tripId) {
    return _trips.doc(tripId).snapshots().map((snap) {
      if (!snap.exists) return null;
      return Trip.fromMap(snap.data()!, snap.id);
    });
  }

  /// Find the trip for a given request id.
  ///
  /// **No `orderBy`** so this query needs only the auto-created single-
  /// field index on `requestId`, not a composite (requestId+createdAt)
  /// index. Since [RequestService.acceptRequest] is atomic, there's at
  /// most one trip per request anyway — so ordering would be a no-op.
  /// If two trips somehow exist (race condition, manual data fix),
  /// `.limit(1)` gives us a deterministic one — we just pick *some*
  /// trip rather than crashing.
  Future<Trip?> findByRequestId(String requestId) async {
    final q = await _trips
        .where('requestId', isEqualTo: requestId)
        .limit(1)
        .get();
    if (q.docs.isEmpty) return null;
    return Trip.fromMap(q.docs.first.data(), q.docs.first.id);
  }

  /// Same as [findByRequestId] but as a live stream. Used by the
  /// requester's request-detail screen to react instantly when a
  /// helper confirms — pops them into the "Help is on the way" toast.
  ///
  /// Logs stream errors to the console (`debugPrint`) so a broken
  /// query / rules violation isn't silently swallowed. If the toast
  /// ever fails to appear, check the device logs first.
  Stream<Trip?> watchByRequestId(String requestId) {
    return _trips
        .where('requestId', isEqualTo: requestId)
        .limit(1)
        .snapshots()
        .handleError((Object e, StackTrace st) {
      // Surfaces composite-index / rules errors. Doesn't crash the
      // stream — downstream sees null and just doesn't render.
      debugPrint('TripService.watchByRequestId($requestId) error: $e');
    }).map((q) {
      if (q.docs.isEmpty) return null;
      return Trip.fromMap(q.docs.first.data(), q.docs.first.id);
    });
  }

  /// Streams every non-completed trip where the current user is the
  /// **requester**. Powers the "Help on the way" banner at the top of
  /// the home screen — appears the instant a helper confirms,
  /// regardless of which screen the requester is currently looking at.
  Stream<List<Trip>> watchActiveForRequester(String requesterUid) {
    return _trips
        .where('requesterUid', isEqualTo: requesterUid)
        .where('status', whereIn: [
          TripStatus.confirmed.wire,
          TripStatus.enRoute.wire,
          TripStatus.atDoor.wire,
        ])
        .snapshots()
        .handleError((Object e, StackTrace st) {
          debugPrint('TripService.watchActiveForRequester error: $e');
        })
        .map((q) =>
            q.docs.map((d) => Trip.fromMap(d.data(), d.id)).toList());
  }

  /// Streams every trip currently assigned to [helperUid] that isn't
  /// yet completed. Used by the helper's home screen to surface an
  /// "ongoing trip" banner if they backgrounded mid-route.
  Stream<List<Trip>> watchActiveForHelper(String helperUid) {
    return _trips
        .where('helperUid', isEqualTo: helperUid)
        .where('status', whereIn: [
          TripStatus.confirmed.wire,
          TripStatus.enRoute.wire,
          TripStatus.atDoor.wire,
        ])
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((q) =>
            q.docs.map((d) => Trip.fromMap(d.data(), d.id)).toList());
  }

  // ── Writes ───────────────────────────────────────────────────────────

  /// Advances the lifecycle. The state machine is not enforced
  /// server-side here — Firestore Security Rules should enforce
  /// (confirmed → enRoute → atDoor → completed) and that only the
  /// helper can move it forward (and only the requester closes it).
  Future<void> updateStatus(String tripId, TripStatus status) async {
    await _trips.doc(tripId).update({
      'status': status.wire,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Pushes the helper's most-recent GPS so the requester's tracking
  /// screen can render movement. Called from a periodic timer on the
  /// helper side while `status == enRoute`. Cheap: a single small
  /// doc update; Firestore charges one write per call. We coalesce
  /// to ~10s on the caller side.
  ///
  /// Also accepts an optional [etaMinutes] update — if the route was
  /// re-computed (e.g. helper took a wrong turn), the requester sees
  /// the new ETA right away.
  Future<void> updateHelperLocation(
    String tripId, {
    required double lat,
    required double lng,
    int? etaMinutes,
  }) async {
    await _trips.doc(tripId).update({
      'helperLat': lat,
      'helperLng': lng,
      'etaMinutes': ?etaMinutes,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Mutates the bring-list mid-trip — e.g. the helper unchecks an
  /// item because they realised they don't have it. Rare but kept
  /// here so the UI doesn't have to read-modify-write by hand.
  Future<void> updateBringList(
      String tripId, List<BringItem> bringList) async {
    await _trips.doc(tripId).update({
      'bringList': bringList.map((e) => e.toMap()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}

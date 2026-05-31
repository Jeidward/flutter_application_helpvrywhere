import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Tracks "who is currently looking at this request" via a per-request
/// subcollection at `requests/{requestId}/viewers/{viewerUid}`.
///
/// The pattern is intentionally simple:
///   • Each open viewer writes their own doc with `updatedAt: serverTimestamp()`.
///   • A periodic heartbeat (every 12 s) re-stamps it, so a viewer
///     whose app got killed without a clean dispose ages out
///     automatically.
///   • Anyone counting active viewers filters for `updatedAt` newer
///     than `now - staleWindow` (30 s by default).
///
/// This gives the requester a real-time "N neighbours are checking
/// your request" feel — and stale viewers can never pile up because
/// the count *only* includes recent heartbeats, regardless of whether
/// the dispose-side cleanup ran.
class ViewerPresenceService {
  ViewerPresenceService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// How often a live viewer re-stamps their doc. Pick a value
  /// noticeably shorter than [staleWindow] so two missed heartbeats
  /// still keep the viewer alive in the count.
  static const Duration heartbeatInterval = Duration(seconds: 12);

  /// Viewers older than this are considered gone. Reads on the
  /// requester side filter against this threshold.
  static const Duration staleWindow = Duration(seconds: 30);

  CollectionReference<Map<String, dynamic>> _viewersOf(String requestId) =>
      _db.collection('requests').doc(requestId).collection('viewers');

  /// Starts marking [viewerUid] as actively viewing [requestId].
  /// Writes the initial doc, then re-stamps every [heartbeatInterval]
  /// until the returned [PresenceHandle.stop] is called (typically
  /// from `dispose()`).
  ///
  /// Returning a handle (instead of e.g. a StreamSubscription) keeps
  /// the call site one-line: just call `handle.stop()` on dispose.
  PresenceHandle startViewing({
    required String requestId,
    required String viewerUid,
  }) {
    final ref = _viewersOf(requestId).doc(viewerUid);

    Future<void> stamp() async {
      try {
        await ref.set({
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('viewer heartbeat failed: $e');
      }
    }

    // Fire-and-forget initial stamp + schedule heartbeat.
    unawaited(stamp());
    final timer = Timer.periodic(heartbeatInterval, (_) => stamp());

    return PresenceHandle._(
      timer: timer,
      stop: () async {
        timer.cancel();
        try {
          await ref.delete();
        } catch (e) {
          debugPrint('viewer cleanup failed: $e');
        }
      },
    );
  }

  /// Live count of distinct viewers currently on [requestId]'s detail
  /// screen.
  ///
  /// - Filters out anyone whose heartbeat is older than [staleWindow]
  ///   (client-side, so we never depend on a Cloud Function for
  ///   cleanup).
  /// - Optional [excludeUid] is for the common case where the
  ///   requester is viewing their own request — they shouldn't count
  ///   themselves in "N neighbours are checking".
  Stream<int> watchActiveViewerCount(
    String requestId, {
    String? excludeUid,
  }) {
    return _viewersOf(requestId).snapshots().map((snap) {
      final cutoff = DateTime.now().subtract(staleWindow);
      var count = 0;
      for (final doc in snap.docs) {
        if (excludeUid != null && doc.id == excludeUid) continue;
        final ts = doc.data()['updatedAt'];
        if (ts is! Timestamp) continue; // server timestamp not yet resolved
        if (ts.toDate().isBefore(cutoff)) continue;
        count++;
      }
      return count;
    }).handleError((Object e, StackTrace st) {
      debugPrint('ViewerPresenceService.watchActiveViewerCount error: $e');
    });
  }
}

/// Tiny wrapper around the timer + cleanup callback so call sites can
/// just store the handle on their State and call `stop()` on dispose.
class PresenceHandle {
  PresenceHandle._({required this.timer, required this.stop});

  final Timer timer;

  /// Stops the heartbeat AND deletes the viewer doc. Idempotent —
  /// safe to call more than once.
  final Future<void> Function() stop;
}

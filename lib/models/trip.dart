import 'package:cloud_firestore/cloud_firestore.dart';

/// Lifecycle of a live "help on the way" trip.
///
///   confirmed → helper accepted, request is paired, neither has set off
///   enRoute   → helper tapped "Start navigation"; live position streaming
///   atDoor    → geofence fired (50 m radius around requester)
///   completed → handshake confirmed by requester ("It's her") or both
///               sides marked done
///
/// This is a separate axis from [RequestStatus]. A request stays
/// `accepted` for the whole life of the trip — the [Trip] doc tracks
/// the finer-grained in-progress state.
enum TripStatus { confirmed, enRoute, atDoor, completed }

extension TripStatusX on TripStatus {
  /// The Firestore string for this enum. Matches the field stored on
  /// `trips/{id}.status` and the one read back in [Trip.fromMap].
  String get wire {
    switch (this) {
      case TripStatus.confirmed:
        return 'confirmed';
      case TripStatus.enRoute:
        return 'enRoute';
      case TripStatus.atDoor:
        return 'atDoor';
      case TripStatus.completed:
        return 'completed';
    }
  }

  static TripStatus fromWire(String? raw) {
    switch (raw) {
      case 'enRoute':
        return TripStatus.enRoute;
      case 'atDoor':
        return TripStatus.atDoor;
      case 'completed':
        return TripStatus.completed;
      case 'confirmed':
      default:
        return TripStatus.confirmed;
    }
  }
}

/// One row in the "what you're bringing" checklist on the confirm-help
/// sheet (step 1). Items can be manually entered, AI-suggested, or
/// pre-filled from the request body.
class BringItem {
  final String label;
  final bool checked;

  /// True when the item came from an AI suggestion. Used so the UI
  /// can render a small "AI" badge next to it.
  final bool fromAi;

  const BringItem({
    required this.label,
    this.checked = false,
    this.fromAi = false,
  });

  BringItem copyWith({String? label, bool? checked, bool? fromAi}) =>
      BringItem(
        label: label ?? this.label,
        checked: checked ?? this.checked,
        fromAi: fromAi ?? this.fromAi,
      );

  Map<String, dynamic> toMap() => {
        'label': label,
        'checked': checked,
        'fromAi': fromAi,
      };

  factory BringItem.fromMap(Map<String, dynamic> m) => BringItem(
        label: (m['label'] ?? '') as String,
        checked: (m['checked'] ?? false) as bool,
        fromAi: (m['fromAi'] ?? false) as bool,
      );
}

/// The live "help on the way" trip — a separate Firestore doc that's
/// created the moment a helper confirms in the step-1 bottom sheet,
/// and ticks through [TripStatus] until both phones agree the help is
/// delivered.
///
/// Stored at `trips/{tripId}`. Identified by [code] for the human-side
/// (e.g. "BLU · 47") — see [TripCodeGenerator].
///
/// Both helper and requester subscribe to the same doc via
/// `TripService.watch(tripId)` so neither phone has to re-derive
/// state — every field on this model is the source of truth.
class Trip {
  final String id;

  /// Human-friendly code like "BLU · 47" — shown on every screen of
  /// the trip so the requester can verify "is this really my helper?"
  /// before opening the door.
  final String code;

  /// Foreign key into the `requests` collection.
  final String requestId;

  final String helperUid;
  final String requesterUid;

  /// Estimated arrival in minutes, captured when the helper confirmed.
  /// Updated as the trip progresses (re-calculated client-side from
  /// the live route).
  final int etaMinutes;

  /// Distance from helper at accept time, in km.
  final double distanceKm;

  /// What the helper said they'd bring. Mix of manually-checked items
  /// and AI suggestions accepted via the "+" button in the sheet.
  final List<BringItem> bringList;

  /// Free-text note from the helper to the requester ("I'll be there
  /// in 20, buzz #1421 when I'm at the door").
  final String helperNote;

  final TripStatus status;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Helper's most recent GPS — pushed periodically (every ~10s)
  /// while the trip is enRoute so the requester's tracking screen
  /// shows the pin closing in. Null until the helper taps "Start
  /// navigation".
  final double? helperLat;
  final double? helperLng;

  const Trip({
    required this.id,
    required this.code,
    required this.requestId,
    required this.helperUid,
    required this.requesterUid,
    required this.etaMinutes,
    required this.distanceKm,
    required this.bringList,
    required this.helperNote,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.helperLat,
    this.helperLng,
  });

  factory Trip.fromMap(Map<String, dynamic> m, String id) {
    final list = (m['bringList'] as List?) ?? const [];
    return Trip(
      id: id,
      code: (m['code'] ?? '') as String,
      requestId: (m['requestId'] ?? '') as String,
      helperUid: (m['helperUid'] ?? '') as String,
      requesterUid: (m['requesterUid'] ?? '') as String,
      etaMinutes: ((m['etaMinutes'] ?? 0) as num).toInt(),
      distanceKm: ((m['distanceKm'] ?? 0) as num).toDouble(),
      bringList: list
          .whereType<Map<String, dynamic>>()
          .map(BringItem.fromMap)
          .toList(),
      helperNote: (m['helperNote'] ?? '') as String,
      status: TripStatusX.fromWire(m['status'] as String?),
      createdAt: _readDate(m['createdAt']) ?? DateTime.now(),
      updatedAt: _readDate(m['updatedAt']) ?? DateTime.now(),
      helperLat: (m['helperLat'] as num?)?.toDouble(),
      helperLng: (m['helperLng'] as num?)?.toDouble(),
    );
  }

  /// Serialises for `set()` on doc creation. Uses
  /// `FieldValue.serverTimestamp()` for both `createdAt` and
  /// `updatedAt` so we don't trust the client clock.
  Map<String, dynamic> toCreateMap() => {
        'code': code,
        'requestId': requestId,
        'helperUid': helperUid,
        'requesterUid': requesterUid,
        'etaMinutes': etaMinutes,
        'distanceKm': distanceKm,
        'bringList': bringList.map((e) => e.toMap()).toList(),
        'helperNote': helperNote,
        'status': status.wire,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        if (helperLat != null) 'helperLat': helperLat,
        if (helperLng != null) 'helperLng': helperLng,
      };

  static DateTime? _readDate(Object? raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return null;
  }
}

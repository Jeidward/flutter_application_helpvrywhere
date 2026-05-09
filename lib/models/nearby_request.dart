import 'package:flutter_application_helpvrywhere/models/request_model.dart';

/// Presentation-layer wrapper around a Firestore [RequestModel]. Holds the
/// raw doc PLUS three computed fields the UI cares about:
///   - [requesterName]    — looked up from the users collection.
///   - [distanceKm]       — distance from the current volunteer in km.
///   - [estimatedMinutes] — rough walking-time estimate.
///
/// All getters delegate to the underlying [request] so existing UI code
/// that referenced fields like `title`, `description`, `latitude`, etc.
/// keeps working without churn.
class NearbyRequest {
  const NearbyRequest({
    required this.request,
    required this.requesterName,
    required this.distanceKm,
    required this.estimatedMinutes,
  });

  final RequestModel request;
  final String requesterName;
  final double distanceKm;
  final int estimatedMinutes;

  // ── Convenience getters that delegate to the Firestore doc ───────────────
  String get id => request.id;
  String get title => request.title;
  String get description => request.description;
  String get categoryRaw => request.category;
  RequestCategory get category => RequestCategoryX.fromRaw(request.category);
  String? get neighborhood => request.location;
  DateTime get postedAt => request.createdAt;
  double get latitude => request.latitude;
  double get longitude => request.longitude;
  String get phone => request.phone;
  String get requesterUserId => request.userId;
}

/// Categories the UI knows how to render with a label and a filter chip.
/// Real Firestore data stores [RequestModel.category] as an arbitrary
/// string (whatever the user typed in the create-request form), so we
/// parse it best-effort and fall back to [other] for anything unknown.
enum RequestCategory { groceries, transport, household, companionship, other }

extension RequestCategoryX on RequestCategory {
  String get label {
    switch (this) {
      case RequestCategory.groceries:
        return 'Groceries';
      case RequestCategory.transport:
        return 'Transport';
      case RequestCategory.household:
        return 'Household';
      case RequestCategory.companionship:
        return 'Companionship';
      case RequestCategory.other:
        return 'Other';
    }
  }

  /// Best-effort string → enum mapping. Case-insensitive, accepts a few
  /// common synonyms so a user typing "shopping" or "ride" still falls
  /// into the right bucket. Anything unrecognized lands in [other].
  static RequestCategory fromRaw(String raw) {
    final s = raw.trim().toLowerCase();
    if (s.isEmpty) return RequestCategory.other;
    if (s.contains('grocer') || s.contains('shop') || s.contains('market')) {
      return RequestCategory.groceries;
    }
    if (s.contains('transport') ||
        s.contains('ride') ||
        s.contains('car') ||
        s.contains('drive')) {
      return RequestCategory.transport;
    }
    if (s.contains('house') ||
        s.contains('home') ||
        s.contains('repair') ||
        s.contains('clean') ||
        s.contains('chore')) {
      return RequestCategory.household;
    }
    if (s.contains('compan') ||
        s.contains('social') ||
        s.contains('talk') ||
        s.contains('visit')) {
      return RequestCategory.companionship;
    }
    return RequestCategory.other;
  }
}

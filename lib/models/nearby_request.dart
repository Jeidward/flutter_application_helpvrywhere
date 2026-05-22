import 'package:flutter/material.dart';
import 'package:flutter_application_helpvrywhere/models/request_model.dart';
import 'package:flutter_application_helpvrywhere/theme/app_theme.dart';

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

  // ── Display helpers used by the new card / detail / map UI ───────────────

  /// "Mrs. Kim" → "MK". Single word → first letter. Empty → "?".
  String get requesterInitials {
    final parts = requesterName
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  /// "0.4 km" / "120 m". Blank when location isn't available yet (km = 0).
  String get distanceLabel {
    if (distanceKm <= 0) return '—';
    if (distanceKm < 1.0) return '${(distanceKm * 1000).round()} m';
    return '${distanceKm.toStringAsFixed(1)} km';
  }

  /// "~15 min" — for the meta tag on the card.
  String get estimatedLabel => '~$estimatedMinutes min';

  /// "5m" / "2h" / "3d" — compact, for the top-right of the card.
  String get postedShort {
    final d = DateTime.now().difference(postedAt);
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }

  /// "5 minutes ago" — long form, for the detail screen.
  String get postedLabel {
    final d = DateTime.now().difference(postedAt);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) {
      final h = d.inHours;
      return '$h ${h == 1 ? "hour" : "hours"} ago';
    }
    final days = d.inDays;
    return '$days ${days == 1 ? "day" : "days"} ago';
  }

  /// Used by the requester header on the detail screen. Falls back to a
  /// generic label when the Firestore doc has no `location` string.
  String get requesterLocation =>
      (neighborhood == null || neighborhood!.trim().isEmpty)
          ? 'Nearby'
          : neighborhood!;
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

  /// Glyph shown inside the [CategoryTag] pill.
  IconData get icon {
    switch (this) {
      case RequestCategory.groceries:
        return Icons.shopping_bag_outlined;
      case RequestCategory.transport:
        return Icons.directions_car_outlined;
      case RequestCategory.household:
        return Icons.home_outlined;
      case RequestCategory.companionship:
        return Icons.favorite_outline;
      case RequestCategory.other:
        return Icons.more_horiz;
    }
  }

  /// Text / icon color for the [CategoryTag] pill + the pulse dot on the
  /// list card. Matches the brand palette in [AppColors].
  Color get foreground {
    switch (this) {
      case RequestCategory.groceries:
        return AppColors.groceriesFg;
      case RequestCategory.transport:
        return AppColors.transportFg;
      case RequestCategory.household:
        return AppColors.householdFg;
      case RequestCategory.companionship:
        return AppColors.techFg;
      case RequestCategory.other:
        return AppColors.darkNavy;
    }
  }

  /// Background of the [CategoryTag] pill.
  Color get background {
    switch (this) {
      case RequestCategory.groceries:
        return AppColors.groceriesBg;
      case RequestCategory.transport:
        return AppColors.transportBg;
      case RequestCategory.household:
        return AppColors.householdBg;
      case RequestCategory.companionship:
        return AppColors.techBg;
      case RequestCategory.other:
        return const Color(0xFFF4F5F8);
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

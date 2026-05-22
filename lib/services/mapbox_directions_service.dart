import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// A single turn from the Mapbox Directions API.
class RouteStep {
  const RouteStep({
    required this.instruction,
    required this.distanceMeters,
    required this.maneuverType,
    required this.maneuverModifier,
    required this.streetName,
    required this.maneuverLat,
    required this.maneuverLng,
  });

  /// Human-readable text — either the `maneuver.instruction` from Mapbox
  /// or a fallback built from type + modifier + street name.
  final String instruction;

  /// Distance to travel for this step (meters). Use [formatted] for UI.
  final double distanceMeters;

  /// `depart` / `arrive` / `turn` / `continue` / `merge` / `roundabout` / …
  final String maneuverType;

  /// `left` / `right` / `straight` / `slight left` / `slight right` / …
  final String maneuverModifier;

  /// Street the user will be on AFTER this maneuver, if Mapbox knows it.
  final String streetName;

  /// Latitude where this maneuver happens — used by the in-app navigation
  /// screen to detect when the user has reached this turn.
  final double maneuverLat;

  /// Longitude where this maneuver happens.
  final double maneuverLng;
}

/// A full walking route returned by Mapbox Directions.
class RouteResult {
  const RouteResult({
    required this.steps,
    required this.geometryLngLat,
    required this.totalDistanceMeters,
    required this.totalDurationSeconds,
  });

  final List<RouteStep> steps;

  /// Every coordinate along the route as [lng, lat] pairs — feed straight
  /// into Mapbox's `LineString` to draw the polyline.
  final List<List<double>> geometryLngLat;

  final double totalDistanceMeters;
  final double totalDurationSeconds;
}

/// Calls the Mapbox Directions API (walking profile) and turns the JSON
/// into typed [RouteResult] / [RouteStep] objects.
///
/// Reads the public token from `.env` (`MAPBOX_TOKEN`) so it never lives
/// in source. Times out at 15 s.
class MapboxDirectionsService {
  static const String _base = 'https://api.mapbox.com/directions/v5/mapbox';

  static String get _token => dotenv.env['MAPBOX_TOKEN'] ?? '';

  /// Returns a walking route. Returns null when Mapbox could not find a
  /// route between the two points (start ≈ end, or no walkable path).
  /// Throws [DirectionsException] on transport/HTTP/parse failures.
  Future<RouteResult?> getWalkingRoute({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  }) async {
    if (_token.isEmpty) {
      throw DirectionsException(
        'MAPBOX_TOKEN missing in .env — cannot fetch directions.',
      );
    }

    // Lng comes first in Mapbox's URL syntax — easy mistake to make.
    final coords = '$fromLng,$fromLat;$toLng,$toLat';
    final uri = Uri.parse(
      '$_base/walking/$coords'
      '?access_token=$_token'
      '&steps=true'
      '&geometries=geojson'
      '&overview=full'
      '&language=en',
    );

    final http.Response res;
    try {
      res = await http.get(uri).timeout(const Duration(seconds: 15));
    } catch (e) {
      throw DirectionsException('Network error talking to Mapbox: $e');
    }

    if (res.statusCode != 200) {
      throw DirectionsException(
        'Mapbox Directions returned ${res.statusCode}: ${res.body}',
      );
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      throw DirectionsException('Could not parse Mapbox response: $e');
    }

    final routes = body['routes'] as List?;
    if (routes == null || routes.isEmpty) return null;

    final route = routes.first as Map<String, dynamic>;

    // Polyline geometry: a list of [lng, lat] pairs.
    final geometry = <List<double>>[];
    final coordsJson =
        (route['geometry'] as Map<String, dynamic>)['coordinates'] as List;
    for (final c in coordsJson) {
      geometry.add([
        (c[0] as num).toDouble(),
        (c[1] as num).toDouble(),
      ]);
    }

    // Turn-by-turn steps live under legs[].steps[].
    final steps = <RouteStep>[];
    final legs = route['legs'] as List? ?? const [];
    for (final leg in legs) {
      final stepList = (leg as Map<String, dynamic>)['steps'] as List? ?? [];
      for (final raw in stepList) {
        final s = raw as Map<String, dynamic>;
        final maneuver = (s['maneuver'] as Map<String, dynamic>?) ?? const {};
        final mtype = (maneuver['type'] as String?) ?? '';
        final mmod = (maneuver['modifier'] as String?) ?? '';
        final street = (s['name'] as String?) ?? '';
        final mapboxInstruction = maneuver['instruction'] as String?;
        // location: [lng, lat] in Mapbox JSON.
        final loc = maneuver['location'] as List?;
        final mLng = loc != null && loc.length >= 2
            ? (loc[0] as num).toDouble()
            : 0.0;
        final mLat = loc != null && loc.length >= 2
            ? (loc[1] as num).toDouble()
            : 0.0;

        steps.add(RouteStep(
          instruction: (mapboxInstruction != null &&
                  mapboxInstruction.trim().isNotEmpty)
              ? mapboxInstruction
              : _fallbackInstruction(mtype, mmod, street),
          distanceMeters: ((s['distance'] as num?) ?? 0).toDouble(),
          maneuverType: mtype,
          maneuverModifier: mmod,
          streetName: street,
          maneuverLat: mLat,
          maneuverLng: mLng,
        ));
      }
    }

    return RouteResult(
      steps: steps,
      geometryLngLat: geometry,
      totalDistanceMeters: ((route['distance'] as num?) ?? 0).toDouble(),
      totalDurationSeconds: ((route['duration'] as num?) ?? 0).toDouble(),
    );
  }

  /// Builds a passable English instruction when Mapbox didn't include one
  /// (older API versions, or when `language` is missing).
  String _fallbackInstruction(String type, String modifier, String street) {
    final on = street.isNotEmpty ? ' on $street' : '';
    final onto = street.isNotEmpty ? ' onto $street' : '';
    switch (type) {
      case 'depart':
        return 'Start walking$on';
      case 'arrive':
        return 'You have arrived';
      case 'turn':
        return modifier.isEmpty ? 'Turn$onto' : 'Turn $modifier$onto';
      case 'continue':
      case 'new name':
        return 'Continue$on';
      case 'merge':
        return 'Merge$onto';
      case 'roundabout':
      case 'rotary':
        return 'Take the roundabout$onto';
      case 'fork':
        return 'At the fork, keep $modifier'.trim();
      default:
        return 'Continue$on';
    }
  }
}

class DirectionsException implements Exception {
  DirectionsException(this.message);
  final String message;

  @override
  String toString() => 'DirectionsException: $message';
}

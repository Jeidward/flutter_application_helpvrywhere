import 'package:geolocator/geolocator.dart';

class LocationService {
  Future<String> getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Check if location services are enabled
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled.');
    }

    // Check for location permissions
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Location permissions are permanently denied, we cannot request permissions.',
      );
    }

    // If permissions are granted, get the current position
    return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        )
        .then((Position position) {
          return 'Latitude: ${position.latitude}, Longitude: ${position.longitude}';
        })
        .catchError((e) {
          throw Exception('Failed to get location: $e');
        });
  }
}

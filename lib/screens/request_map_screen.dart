import 'package:flutter/material.dart';
import 'package:flutter_application_helpvrywhere/services/location_service.dart';
import 'package:geolocator/geolocator.dart';

class RequestMapScreen extends StatelessWidget {
  const RequestMapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Home')),
      //current location
      body: FutureBuilder<Position>(
        future: LocationService().getCurrentLocation(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (!snapshot.hasData) {
            return const Center(child: Text('No location found'));
          }

          final position = snapshot.data!;

          return Center(
            child: Text(
              'Latitude: ${position.latitude}\nLongitude: ${position.longitude}',
              textAlign: TextAlign.center,
            ),
          );
        },
      ),
    );
  }
}

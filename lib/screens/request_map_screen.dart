import 'package:flutter/material.dart';
import 'package:flutter_application_helpvrywhere/services/location_service.dart';

class RequestMapScreen extends StatelessWidget {
  const RequestMapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Home')),
      //current location
      body: FutureBuilder<String>(
        future: LocationService().getCurrentLocation(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Text('Error: ${snapshot.error}');
          } else {
            return Text(snapshot.data ?? 'No location found');
          }
        },
      ),
    );
  }
}

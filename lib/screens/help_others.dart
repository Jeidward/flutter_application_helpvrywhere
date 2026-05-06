import 'package:flutter_application_helpvrywhere/screens/request_map_screen.dart';
import 'package:flutter/material.dart';

class HelpOthersTab extends StatelessWidget {
  const HelpOthersTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.volunteer_activism, size: 60),
          SizedBox(height: 16),

          Text(
            "Help people around you",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),

          SizedBox(height: 8),

          Text(
            "View nearby requests and offer your help.",
            textAlign: TextAlign.center,
          ),

          SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: Icon(Icons.map),
              label: Text("View nearby requests"),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => RequestMapScreen()),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

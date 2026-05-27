import 'package:flutter/material.dart';
import 'package:flutter_application_helpvrywhere/screens/request_list_screen.dart';

class MyRequestTab extends StatelessWidget {
  const MyRequestTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "My requests",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 12),

            Expanded(child: RequestListWidget()),
          ],
        ),
      ),
    );
  }
}

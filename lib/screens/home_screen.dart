import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_helpvrywhere/models/user_model.dart';
import 'package:flutter_application_helpvrywhere/screens/request_map_screen.dart';
import 'package:flutter_application_helpvrywhere/screens/request_creation_screen.dart';
import 'package:flutter_application_helpvrywhere/services/auth_service.dart'; // for logout
import 'package:flutter_application_helpvrywhere/screens/request_list_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text("good morning", style: TextStyle(fontSize: 15)),
            Text("Seonwoo", style: TextStyle(fontSize: 25)),
          ],
        ),
        actions: [
          // Profile button (temporary — will be expanded to full profile screen later)
          IconButton(
            onPressed: () => _showProfileDialog(context),
            icon: const Icon(Icons.person),
          ),
          // Logout button for testing
          IconButton(
            onPressed: () async {
              // Confirm before logging out
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Log out?'),
                  content: const Text('Are you sure you want to log out?'),
                  actions: [
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Log Out'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              );
              if (confirm != true) return;

              await AuthService().signOut();
              if (context.mounted) {
                Navigator.pushReplacementNamed(context, '/');
              }
            },
            icon: const Icon(Icons.logout),
          ),
          IconButton(
            onPressed: () {},
            icon: CircleAvatar(backgroundColor: Colors.blueGrey),
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          spacing: 10,
          children: [
            Row(
              spacing: 10,
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => RequestMapScreen(),
                        ),
                      );
                    },
                    child: Container(
                      height: 135,
                      padding: EdgeInsets.all(25),
                      alignment: Alignment.bottomLeft,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: Color.fromARGB(249, 255, 247, 153),
                      ),
                      child: Text(
                        "Find nearby requests",
                        style: TextStyle(fontSize: 20),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () {},
                    child: Container(
                      height: 135,
                      padding: EdgeInsets.all(25),
                      alignment: Alignment.bottomLeft,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: Color.fromARGB(228, 148, 223, 255),
                      ),
                      child: Text(
                        "AI tech support",
                        style: TextStyle(fontSize: 20),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Row(
              spacing: 10,
              children: [
                Expanded(
                  child: Container(
                    height: 135,
                    padding: EdgeInsets.all(25),
                    alignment: Alignment.bottomLeft,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: Color.fromARGB(236, 205, 255, 144),
                    ),
                    child: Text(
                      "My help history",
                      style: TextStyle(fontSize: 20),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => RequestCreationScreen(),
                        ),
                      );
                    },
                    child: Container(
                      height: 135,
                      padding: EdgeInsets.all(25),
                      alignment: Alignment.bottomLeft,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: Color.fromARGB(139, 219, 165, 255),
                      ),
                      child: Text(
                        "Create a request",
                        style: TextStyle(fontSize: 20),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Row(
              spacing: 10,
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => RequestListScreen(),
                        ),
                      );
                    },
                    child: Container(
                      height: 135,
                      padding: EdgeInsets.all(25),
                      alignment: Alignment.bottomLeft,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: Color.fromARGB(139, 219, 165, 255),
                      ),
                      child: Text(
                        "Get all my request",
                        style: TextStyle(fontSize: 20),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Shows a dialog with phone verification status and verify/unlink action.
// Will be expanded into a proper profile screen later.
Future<void> _showProfileDialog(BuildContext context) async {
  final authService = AuthService();
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;

  final user = await authService.getUserDocument(uid);
  if (!context.mounted || user == null) return;

  final isVerified = user.phoneVerifiedUntil != null &&
      user.phoneVerifiedUntil!.isAfter(DateTime.now());

  await showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Profile'),
      content: Text(
        isVerified
            ? 'Phone verified until: ${user.phoneVerifiedUntil!.toLocal().toString().split(' ')[0]}'
            : 'Phone not verified.',
      ),
      actions: [
        if (isVerified)
          ElevatedButton(
            onPressed: () async {
              await authService.unlinkPhone();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Unlink Phone'),
          )
        else
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/verify-phone');
            },
            child: const Text('Verify Phone'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

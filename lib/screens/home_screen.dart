import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_helpvrywhere/models/user_model.dart';
import 'package:flutter_application_helpvrywhere/screens/request_map_screen.dart';
import 'package:flutter_application_helpvrywhere/screens/request_creation_screen.dart';
import 'package:flutter_application_helpvrywhere/services/auth_service.dart'; // for logout
import 'package:flutter_application_helpvrywhere/screens/request_list_screen.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart'; // For overlay window
import 'package:flutter/services.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  String _getCurrentTimeDate() {
    final now = DateTime.now();
    final hour = now.hour;
    if (hour < 12) {
      return "Good morning";
    } else if (hour < 18) {
      return "Good afternoon";
    } else {
      return "Good evening";
    }
  }

  Widget _buildCard({
    required IconData icons,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 150,
          padding: EdgeInsets.all(25),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: color,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icons, size: 28),
              Text(label, style: TextStyle(fontSize: 20)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        //for now futurBuilder, later can use provider or riverpod to avoid fetching user doc every time we open home screen, because it is not efficient
        title: FutureBuilder<UserModel?>(
          future: AuthService().getUserDocument(
            FirebaseAuth.instance.currentUser?.uid ?? '',
          ),
          builder: (context, snapshot) {
            final name = snapshot.data?.username ?? "User";
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_getCurrentTimeDate(), style: TextStyle(fontSize: 20)),
                Text(name, style: TextStyle(fontSize: 25)),
              ],
            );
          },
        ),
        actions: [
          IconButton(
            onPressed: () => _showProfileDialog(context),
            icon: const Icon(Icons.person),
          ),
          IconButton(
            onPressed: () async {
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 20),
            Text(
              "What would you like to do?",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Row(
              spacing: 10,
              children: [
                _buildCard(
                  icons: Icons.location_on,
                  label: "Find nearby request",
                  color: Color.fromARGB(249, 255, 247, 153),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => RequestMapScreen()),
                  ),
                ),
                _buildCard(
                  icons: Icons.smart_toy,
                  label: "AI tech support",
                  color: Color.fromARGB(228, 148, 223, 255),
                  onTap: () async {
                    final platform = MethodChannel('app/background');

                    bool granted =
                        await FlutterOverlayWindow.isPermissionGranted();

                    if (!granted) {
                      final result =
                          await FlutterOverlayWindow.requestPermission();
                      granted = result == true;
                    }

                    if (granted) {
                      await FlutterOverlayWindow.showOverlay(
                        enableDrag: true,
                        height: 450,
                        width: 600,
                        alignment: OverlayAlignment.center,
                        overlayTitle: "Overlay",
                        overlayContent: "Running",
                      );
                      await Future.delayed(const Duration(milliseconds: 500));

                      await platform.invokeMethod('moveToBackground');
                    }
                  },
                ),
              ],
            ),
            Row(
              spacing: 10,
              children: [
                _buildCard(
                  icons: Icons.back_hand,
                  label: "My help history",
                  color: Color.fromARGB(236, 205, 255, 144),
                  onTap: () {},
                ),
                _buildCard(
                  icons: Icons.add,
                  label: "Create a request",
                  color: Color.fromARGB(139, 219, 165, 255),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => RequestCreationScreen(),
                    ),
                  ),
                ),
              ],
            ),
            Row(
              spacing: 10,
              children: [
                _buildCard(
                  icons: Icons.list_alt,
                  label: "Get all my request",
                  color: Color.fromARGB(139, 219, 165, 255),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => RequestListScreen(),
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

Future<void> _showProfileDialog(BuildContext context) async {
  final authService = AuthService();
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;

  final user = await authService.getUserDocument(uid);
  if (!context.mounted || user == null) return;

  final isVerified =
      user.phoneVerifiedUntil != null &&
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

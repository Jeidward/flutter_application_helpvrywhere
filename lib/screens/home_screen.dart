import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_helpvrywhere/models/user_model.dart';
import 'package:flutter_application_helpvrywhere/screens/profile_screen.dart';
import 'package:flutter_application_helpvrywhere/screens/tutorial_screen.dart';
import 'package:flutter_application_helpvrywhere/screens/request_map_screen.dart';
import 'package:flutter_application_helpvrywhere/screens/request_creation_screen.dart';
import 'package:flutter_application_helpvrywhere/services/auth_service.dart';
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
          // Help icon — opens onboarding tutorial dialog
          IconButton(
            onPressed: () => showTutorialDialog(context),
            icon: const Icon(Icons.help_outline),
          ),
          // Profile photo as entry point — opens ProfileDialog
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () => showProfileDialog(context),
              child: FutureBuilder<UserModel?>(
                future: AuthService().getUserDocument(
                  FirebaseAuth.instance.currentUser?.uid ?? '',
                ),
                builder: (context, snapshot) {
                  final photoUrl = snapshot.data?.photoUrl;
                  return CircleAvatar(
                    backgroundColor: Colors.blueGrey.shade100,
                    backgroundImage:
                        photoUrl != null ? NetworkImage(photoUrl) : null,
                    child: photoUrl == null
                        ? const Icon(Icons.person, color: Colors.blueGrey)
                        : null,
                  );
                },
              ),
            ),
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


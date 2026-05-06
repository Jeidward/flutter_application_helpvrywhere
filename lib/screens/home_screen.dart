import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_helpvrywhere/models/user_model.dart';
import 'package:flutter_application_helpvrywhere/screens/profile_screen.dart';
import 'package:flutter_application_helpvrywhere/screens/tutorial_screen.dart';
import 'package:flutter_application_helpvrywhere/services/auth_service.dart';
import 'package:flutter_application_helpvrywhere/screens/help_others.dart';
import 'package:flutter_application_helpvrywhere/screens/need_help.dart';

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

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: FutureBuilder<UserModel?>(
            future: AuthService().getUserDocument(
              FirebaseAuth.instance.currentUser?.uid ?? '',
            ),
            builder: (context, snapshot) {
              final name = snapshot.data?.username ?? "User";
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_getCurrentTimeDate(), style: TextStyle(fontSize: 16)),
                  Text(name, style: TextStyle(fontSize: 20)),
                ],
              );
            },
          ),

          actions: [
            IconButton(
              onPressed: () => showTutorialDialog(context),
              icon: const Icon(Icons.help_outline),
            ),
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
                      backgroundImage: photoUrl != null
                          ? NetworkImage(photoUrl)
                          : null,
                      child: photoUrl == null
                          ? const Icon(Icons.person, color: Colors.blueGrey)
                          : null,
                    );
                  },
                ),
              ),
            ),
          ],

          bottom: const TabBar(
            tabs: [
              Tab(text: "I need help"),
              Tab(text: "Help others"),
            ],
          ),
        ),

        body: const TabBarView(children: [NeedHelpTab(), HelpOthersTab()]),
      ),
    );
  }
}

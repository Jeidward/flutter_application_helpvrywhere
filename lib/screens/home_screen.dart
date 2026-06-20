import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_helpvrywhere/models/user_model.dart';
import 'package:flutter_application_helpvrywhere/screens/conversations_screen.dart';
import 'package:flutter_application_helpvrywhere/screens/my_request_tab.dart';
import 'package:flutter_application_helpvrywhere/screens/how_to_guide_screen.dart';
import 'package:flutter_application_helpvrywhere/screens/profile_screen.dart';
import 'package:flutter_application_helpvrywhere/screens/request_creation_screen.dart';
import 'package:flutter_application_helpvrywhere/screens/request_map_screen.dart';
import 'package:flutter_application_helpvrywhere/services/auth_service.dart';
import 'home_tab_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();

    _pages = [
      HomeTab(onNavigate: _onTabSelected),
      // Tab 1 (the map icon) goes straight to the nearby-requests map
      // — the old "Help people around you" placeholder is gone.
      const RequestMapScreen(),
      ConversationsScreen(),
      const MyRequestTab(),
    ];
  }

  int _currentIndex = 0;

  late final List<Widget> _pages;

  void _onTabSelected(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  String _getCurrentTimeDate() {
    final hour = DateTime.now().hour;
    if (hour < 12) return "Good morning";
    if (hour < 18) return "Good afternoon";
    return "Good evening";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ================= HEADER =================
      appBar: AppBar(
        // [donghwan] Temporary fix: under senior mode (1.3x text scaling)
        // the default toolbar height was clipping the greeting + name
        // column. Bumped to 80 and forced single-line text with ellipsis.
        // Please double-check / replace when the senior home variant lands.
        toolbarHeight: 80,
        title: FutureBuilder<UserModel?>(
          future: AuthService().getUserDocument(
            FirebaseAuth.instance.currentUser?.uid ?? '',
          ),
          builder: (context, snapshot) {
            final name = snapshot.data?.username ?? "User";

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _getCurrentTimeDate(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            );
          },
        ),

        actions: [
          IconButton(
            // Open the in-app how-to guide (picture-by-picture walkthrough)
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const HowToGuideScreen(),
              ),
            ),
            icon: const Icon(Icons.help_outline),
            iconSize: 30,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
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
                    radius: 22,
                    backgroundImage: photoUrl != null
                        ? NetworkImage(photoUrl)
                        : null,
                    child: photoUrl == null
                        ? const Icon(
                            Icons.person,
                            size: 26,
                            color: Colors.blueGrey,
                          )
                        : null,
                  );
                },
              ),
            ),
          ),
        ],
      ),

      // ================= BODY =================
      body: IndexedStack(index: _currentIndex, children: _pages),

      // ================= FLOATING BUTTON =================
      floatingActionButton: SizedBox(
        height: 64,
        width: 64,
        child: FloatingActionButton(
          backgroundColor: const Color(0xFF1565C0),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RequestCreationScreen()),
            );
          },
          child: const Icon(Icons.add, color: Colors.white, size: 32),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,

      // ================= BOTTOM NAV =================
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: Colors.grey.shade300, width: 1),
          ),
        ),
        child: BottomAppBar(
          color: Colors.white,
          elevation: 0,
          shape: const CircularNotchedRectangle(),
          notchMargin: 10,
          child: SizedBox(
            height: 68,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                IconButton(
                  icon: const Icon(Icons.home),
                  iconSize: 28,
                  color: _currentIndex == 0 ? Colors.blue : Colors.grey,
                  onPressed: () => _onTabSelected(0),
                ),

                IconButton(
                  icon: const Icon(Icons.map),
                  iconSize: 28,
                  color: _currentIndex == 1 ? Colors.blue : Colors.grey,
                  onPressed: () => _onTabSelected(1),
                ),

                const SizedBox(width: 50),

                IconButton(
                  icon: const Icon(Icons.chat_bubble_outline),
                  iconSize: 28,
                  color: _currentIndex == 2 ? Colors.blue : Colors.grey,
                  onPressed: () => _onTabSelected(2),
                ),

                IconButton(
                  icon: const Icon(Icons.list_alt),
                  iconSize: 28,
                  color: _currentIndex == 3 ? Colors.blue : Colors.grey,
                  onPressed: () => _onTabSelected(3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

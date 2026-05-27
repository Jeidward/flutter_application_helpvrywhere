import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import 'package:flutter_application_helpvrywhere/screens/help_others.dart';
import 'package:flutter_application_helpvrywhere/screens/my_request_tab.dart';
import 'package:flutter_application_helpvrywhere/services/speech_bridge.dart';

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(
            "Home",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 10),

          // ===================== HELP OTHERS =====================
          _HomeCard(
            color: Colors.blue,
            icon: Icons.location_on,
            title: "Offer to help nearby",
            subtitle: "See requests around you. Lend a help to a neighbor",
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HelpOthersTab()),
              );
            },
          ),

          const SizedBox(height: 16),

          // ===================== MY REQUESTS =====================
          _HomeCard(
            color: Colors.green,
            icon: Icons.favorite,
            title: "My request",
            subtitle: "See my current request for help",
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MyRequestTab()),
              );
            },
          ),

          const SizedBox(height: 16),

          // ===================== AI HELPER (OVERLAY FLOW) =====================
          _HomeCard(
            color: Colors.black,
            icon: Icons.smart_toy,
            title: "Ask the AI helper",
            subtitle: "I'll show you how, step by step",
            onTap: () async {
              final platform = MethodChannel('app/background');

              bool granted = await FlutterOverlayWindow.isPermissionGranted();

              if (!granted) {
                final result = await FlutterOverlayWindow.requestPermission();
                granted = result == true;
              }

              if (granted) {
                await SpeechBridge.instance.requestPermissionAndInit();

                final screenshotChannel = MethodChannel('app/screenshot');

                try {
                  await screenshotChannel.invokeMethod<bool>(
                    'requestScreenCapture',
                  );
                } catch (e) {
                  debugPrint('requestScreenCapture failed: $e');
                }

                await FlutterOverlayWindow.showOverlay(
                  enableDrag: false,
                  height: 1100,
                  width: WindowSize.matchParent,
                  alignment: OverlayAlignment.bottomCenter,
                  flag: OverlayFlag.focusPointer,
                  overlayTitle: "Overlay",
                  overlayContent: "Running",
                );

                await platform.invokeMethod('moveToBackground');
              }
            },
          ),
        ],
      ),
    );
  }
}

class _HomeCard extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _HomeCard({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 140,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Container(
              width: 55,
              height: 55,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),

            const SizedBox(width: 16),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

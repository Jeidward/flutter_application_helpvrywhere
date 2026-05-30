import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter_application_helpvrywhere/services/speech_bridge.dart';

class HomeTab extends StatelessWidget {
  final Function(int) onNavigate;

  const HomeTab({super.key, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Home",
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 10),

          // ===================== HELP OTHERS =====================
          _HomeCard(
            color: Colors.blue,
            icon: Icons.location_on,
            title: "Offer to help nearby",
            subtitle: "See requests around you. Lend a help to a neighbor",
            onTap: () {
              onNavigate(1);
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
              onNavigate(3);
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
      // [donghwan] Temporary fix: under senior mode (1.3x text scaling)
      // the fixed 120px card height was overflowing and the title text was
      // breaking the row layout. Switched to minHeight and capped the text
      // to 2 lines with ellipsis. Please double-check / replace when the
      // senior home variant lands.
      child: Container(
        constraints: const BoxConstraints(minHeight: 120),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: Colors.white, size: 36),
            ),

            const SizedBox(width: 20, height: 30),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 16,
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

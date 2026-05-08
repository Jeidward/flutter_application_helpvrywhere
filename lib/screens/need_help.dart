import 'package:flutter/material.dart';
import 'package:flutter_application_helpvrywhere/screens/request_creation_screen.dart';
import 'package:flutter_application_helpvrywhere/screens/request_list_screen.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart'; // For overlay window
import 'package:flutter/services.dart';
import 'package:flutter_application_helpvrywhere/services/speech_bridge.dart';

class NeedHelpTab extends StatelessWidget {
  const NeedHelpTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCard(
              icons: Icons.smart_toy,
              label: "AI support",
              color: Theme.of(context).colorScheme.primaryContainer,
              onTap: () async {
                final platform = MethodChannel('app/background');

                bool granted = await FlutterOverlayWindow.isPermissionGranted();

                if (!granted) {
                  final result = await FlutterOverlayWindow.requestPermission();
                  granted = result == true;
                }

                if (granted) {
                  await SpeechBridge.instance.requestPermissionAndInit();

                  // CRITICAL: ask for the screen-capture permission RIGHT NOW
                  // (while the app is still in the foreground). If we wait
                  // until the user already navigated to WhatsApp/etc. and
                  // then prompt, the permission dialog drags our app back to
                  // the foreground and the resulting screenshot captures US,
                  // not the app the user is actually trying to use.
                  final screenshotChannel = MethodChannel('app/screenshot');
                  try {
                    await screenshotChannel
                        .invokeMethod<bool>('requestScreenCapture');
                  } catch (e) {
                    debugPrint('requestScreenCapture failed: $e');
                  }

                  await FlutterOverlayWindow.showOverlay(
                    enableDrag: false,
                    height: 1150,
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
            const SizedBox(height: 16),

            Text(
              "My requests",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 12),

            Expanded(child: RequestListWidget()),
          ],
        ),
      ),

      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => RequestCreationScreen()),
          );
        },
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

Widget _buildCard({
  required IconData icons,
  required String label,
  required Color color,
  required VoidCallback onTap,
}) {
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(20),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: color,
      ),
      child: Row(
        children: [
          Icon(icons, size: 28),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontSize: 18)),
        ],
      ),
    ),
  );
}

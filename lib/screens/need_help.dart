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

                  // Encourage (but don't block on) enabling the accessibility
                  // service — that's how we get perfectly-localized thumbnails.
                  // If the user declines, we fall back to the AI's bbox guess.
                  final hasA11y =
                      await SpeechBridge.instance.isAccessibilityEnabled();
                  if (!hasA11y && context.mounted) {
                    final keepGoing =
                        await _showAccessibilityOnboarding(context);
                    if (!keepGoing) return; // user went to Settings; abort
                  }

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
                    // Bottom-anchored panel. Tuned so the listening card
                    // — including its 3 control buttons — clears Android's
                    // gesture nav bar on Pixel-class devices (which can
                    // be 60–80 dp tall, way more than the 32 we initially
                    // budgeted for). 1100 px ≈ 367 dp on 3× density;
                    // still ~30 % shorter than the original 1200.
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

/// Friendly first-run dialog explaining why we want the accessibility
/// permission. Returns true if the caller should continue with the
/// overlay flow ("Skip for now"), false if the user opened Settings
/// (they'll re-tap "AI Support" once they're back).
Future<bool> _showAccessibilityOnboarding(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.accessibility_new, color: Color(0xFF4A90E2), size: 28),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'One more thing',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'To show you EXACTLY which button to tap, the assistant needs '
            'permission to read what is on your screen.',
            style: TextStyle(fontSize: 15, height: 1.4),
          ),
          SizedBox(height: 12),
          Text(
            'Without it the assistant still works, but the picture of the '
            'button might not match perfectly.',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: Color(0xFF6B7280),
            ),
          ),
          SizedBox(height: 12),
          Text(
            'On the next screen, find "HelpEverywhere" and turn it on.',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              fontStyle: FontStyle.italic,
              color: Color(0xFF6B7280),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Skip for now'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4A90E2),
            foregroundColor: Colors.white,
          ),
          onPressed: () async {
            Navigator.of(ctx).pop(false);
            await SpeechBridge.instance.openAccessibilitySettings();
          },
          child: const Text('Open Settings'),
        ),
      ],
    ),
  );
  return result ?? true;
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

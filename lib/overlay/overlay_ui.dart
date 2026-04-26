import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

/// Change this file to change the overlay
class OverlayUI extends StatelessWidget {
  const OverlayUI({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black12,
      child: Center(
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("AI Assistant", style: TextStyle(color: Colors.white)),
              const SizedBox(height: 10),

              ElevatedButton(
                onPressed: () {
                  FlutterOverlayWindow.shareData("ping");
                },
                child: const Text("Send data"),
              ),

              ElevatedButton(
                onPressed: () async {
                  await FlutterOverlayWindow.closeOverlay();
                },
                child: const Text("Close"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

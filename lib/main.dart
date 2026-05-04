import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_helpvrywhere/firebase_options.dart';
import 'package:flutter_application_helpvrywhere/screens/auth_wrapper.dart';
import 'package:flutter_application_helpvrywhere/screens/login_screen.dart';
import 'package:flutter_application_helpvrywhere/screens/request_map_screen.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_application_helpvrywhere/overlay/overlay_ui.dart';
import 'package:flutter_application_helpvrywhere/services/speech_bridge.dart';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Listen for overlay → main app messages (start/stop speech).
  print("!!! MAIN APP IS STARTING !!!");
  SpeechBridge.instance.registerOverlayListener();
  FlutterNativeSplash.remove();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'HelpEverywhere',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) =>
            const AuthWrapper(), // was HomeScreen, now checks auth state
        '/login': (context) => const LoginScreen(),
        '/nearby-request': (context) => const RequestMapScreen(),
      },
    );
  }
}

@pragma("vm:entry-point")
void overlayMain() {
  runApp(
    const MaterialApp(debugShowCheckedModeBanner: false, home: OverlayUI()),
  );
}

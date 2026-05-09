import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_helpvrywhere/firebase_options.dart';
import 'package:flutter_application_helpvrywhere/screens/auth_wrapper.dart';
import 'package:flutter_application_helpvrywhere/screens/login_screen.dart';
import 'package:flutter_application_helpvrywhere/screens/request_map_screen.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_application_helpvrywhere/overlay/overlay_ui.dart';
import 'package:flutter_application_helpvrywhere/services/speech_bridge.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'screens/ai_guide_screen.dart';


void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Load .env BEFORE anything that needs a token. The .env file is bundled
  // as a Flutter asset (see pubspec.yaml) and lives ONLY on the local
  // machine — it's gitignored, so secrets never reach the repo.
  // Make sure `.env.example` exists for teammates as a schema reference.
  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    debugPrint(
      '!!! .env failed to load: $e — copy .env.example to .env and '
      'fill in your tokens.',
    );
  }

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Mapbox needs its access token BEFORE any MapWidget tries to render —
  // otherwise the SDK refuses to load tiles and you get a blank/gray map.
  final mapboxToken = dotenv.env['MAPBOX_TOKEN'] ?? '';
  if (mapboxToken.isNotEmpty) {
    MapboxOptions.setAccessToken(mapboxToken);
  } else {
    debugPrint('!!! MAPBOX_TOKEN missing in .env — maps will not load.');
  }

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
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: const Color.fromARGB(255, 91, 167, 217),
            ).copyWith(
              secondary: const Color(0xFF6FCF97),
              tertiary: const Color(0xFFFFC857),
            ),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const AuthWrapper(),
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

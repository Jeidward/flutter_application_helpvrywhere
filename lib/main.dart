import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_helpvrywhere/firebase_options.dart';
import 'package:flutter_application_helpvrywhere/screens/auth_wrapper.dart';
import 'package:flutter_application_helpvrywhere/screens/login_screen.dart';
import 'package:flutter_application_helpvrywhere/screens/phone_verification_screen.dart';
import 'package:flutter_application_helpvrywhere/screens/registration_screen.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
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
        '/': (context) => const AuthWrapper(), // was HomeScreen, now checks auth state
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegistrationScreen(),
        '/verify-phone': (context) => const PhoneVerificationScreen(),
      },
    );
  }
}

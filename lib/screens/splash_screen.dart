import 'package:flutter/material.dart';

//this file is for splash screen, if you do not know what it is, no worries. It is the first screen that shows up when you open the app, it is usually used to show the logo of the app and some loading animation. You can customize it as you like, but for now, we will just use a placeholder.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Placeholder();
  }
}
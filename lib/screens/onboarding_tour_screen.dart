import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'login_screen.dart';

/// Full-screen onboarding tour. Four swipeable pages introducing the
/// app's main features, ending with a CTA to create an account or sign in.
///
/// Used both during initial onboarding (Welcome → Persona → here) and as
/// a "Replay tutorial" entry from the Profile dialog.
class OnboardingTourScreen extends StatefulWidget {
  const OnboardingTourScreen({super.key});

  @override
  State<OnboardingTourScreen> createState() => _OnboardingTourScreenState();
}

class _OnboardingTourScreenState extends State<OnboardingTourScreen> {
  static const _darkBg = Color(0xFF1A1A1A);
  static const _subtleText = Color(0xFF6B7280);
  static const _linkBlue = Color(0xFF5BA7D9);
  static const _accentBlue = Color(0xFF5BA7D9);
  static const _accentGreen = Color(0xFF6FCF97);
  static const _accentLightBlue = Color(0xFFD6EAF8);
  static const _accentLightGreen = Color(0xFFD8F3E2);
  static const _accentLightGray = Color(0xFFF3F4F6);

  final _pageController = PageController();
  int _page = 0;

  late final List<_TourPage> _pages = const [
    _TourPage(
      icon: Icons.location_on,
      iconColor: _accentBlue,
      bg: _accentLightBlue,
      title: 'Find help nearby',
      description:
          'Discover requests from neighbors on an interactive map. Pick something close to home and lend a quick hand.',
    ),
    _TourPage(
      icon: Icons.favorite_outline,
      iconColor: _accentGreen,
      bg: _accentLightGreen,
      title: 'Lend a hand',
      description:
          'Offer your time, skills, or spare supplies. Small acts add up to a stronger neighborhood.',
    ),
    _TourPage(
      icon: Icons.smart_toy_outlined,
      iconColor: _darkBg,
      bg: _accentLightGray,
      title: 'An AI guide on every screen',
      description:
          'Share your screen with our AI and it will walk through any task — calls, settings, messaging — with visual highlights and plain-language steps.',
    ),
    _TourPage(
      icon: Icons.groups_outlined,
      iconColor: Colors.white,
      bg: _darkBg,
      title: 'Join your community',
      description:
          'Create an account to start posting, responding, and connecting with neighbors near you.',
      isFinal: true,
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool get _isLast => _page == _pages.length - 1;

  void _next() {
    if (_isLast) return;
    _pageController.nextPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _back() {
    if (_page == 0) return;
    _pageController.previousPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  /// Exit the tour. For first-run onboarding this means going to LoginScreen.
  /// (Replay-from-Profile case will simply pop back via the appbar back.)
  void _exitToLogin() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Top row: Skip on right (hidden on last page since CTAs are there)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!_isLast)
                    TextButton(
                      onPressed: _exitToLogin,
                      child: const Text(
                        'Skip',
                        style: TextStyle(
                          fontSize: 14,
                          color: _subtleText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ScrollConfiguration(
                behavior: _AllPointersScrollBehavior(),
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _pages.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (_, i) => _TourPageContent(page: _pages[i]),
                ),
              ),
            ),
            // Dots indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages.length, (i) {
                final active = i == _page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active ? _linkBlue : const Color(0xFFD1D5DB),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            const SizedBox(height: 20),
            // Bottom actions — different on final page
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: _isLast
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            // TODO(B4+B5+B6): wire to LoginScreen w/ auto registration dialog
                            onPressed: _exitToLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _linkBlue,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                              ),
                            ),
                            child: const Text(
                              'Create account',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 52,
                          child: OutlinedButton(
                            onPressed: _exitToLogin,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _darkBg,
                              side: const BorderSide(color: Color(0xFFE5E7EB)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                              ),
                            ),
                            child: const Text(
                              'Sign in',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: _page == 0 ? null : _back,
                          child: Text(
                            'Back',
                            style: TextStyle(
                              fontSize: 14,
                              color: _page == 0
                                  ? const Color(0xFFD1D5DB)
                                  : _subtleText,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 48,
                          child: ElevatedButton(
                            onPressed: _next,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _linkBlue,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 22, vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Next',
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600),
                                ),
                                SizedBox(width: 6),
                                Icon(Icons.arrow_forward, size: 18),
                              ],
                            ),
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

/// Data class for one tour page.
class _TourPage {
  final IconData icon;
  final Color iconColor;
  final Color bg;
  final String title;
  final String description;
  final bool isFinal;
  const _TourPage({
    required this.icon,
    required this.iconColor,
    required this.bg,
    required this.title,
    required this.description,
    this.isFinal = false,
  });
}

class _TourPageContent extends StatelessWidget {
  final _TourPage page;
  const _TourPageContent({required this.page});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              color: page.bg,
              shape: BoxShape.circle,
            ),
            child: Icon(page.icon, size: 72, color: page.iconColor),
          ),
          const SizedBox(height: 36),
          Text(
            page.title,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A1A),
              height: 1.2,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          Text(
            page.description,
            style: const TextStyle(
              fontSize: 15,
              color: Color(0xFF6B7280),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Enables mouse drag for the PageView on web/desktop.
class _AllPointersScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
      };
}

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../theme/profile_styles.dart';

/// Allow PageView to be swiped by mouse drag on web/desktop.
class _AllPointersScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
      };
}

/// Shows the app onboarding tutorial as a swipeable dialog.
/// Called after successful registration and from the profile dialog
/// (How to use this app).
Future<void> showTutorialDialog(BuildContext context) async {
  await showDialog(
    context: context,
    builder: (_) => const _TutorialDialog(),
  );
}

class _TutorialDialog extends StatefulWidget {
  const _TutorialDialog();

  @override
  State<_TutorialDialog> createState() => _TutorialDialogState();
}

class _TutorialDialogState extends State<_TutorialDialog> {
  final _pageController = PageController();
  int _currentPage = 0;

  // Placeholder pages — fill in image/title/description later
  static const _pages = <_TutorialPage>[
    _TutorialPage(title: '', description: ''),
    _TutorialPage(title: '', description: ''),
    _TutorialPage(title: '', description: ''),
    _TutorialPage(title: '', description: ''),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool get _isLastPage => _currentPage == _pages.length - 1;

  void _next() {
    if (_isLastPage) {
      Navigator.pop(context);
    } else {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with Skip button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 48),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Skip'),
                  ),
                ],
              ),
            ),

            // Swipeable pages (mouse drag enabled for web/desktop)
            SizedBox(
              height: 380,
              child: ScrollConfiguration(
                behavior: _AllPointersScrollBehavior(),
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _pages.length,
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  itemBuilder: (_, index) =>
                      _TutorialPageContent(page: _pages[index]),
                ),
              ),
            ),

            // Page indicator dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages.length, (i) {
                final active = i == _currentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 20 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active
                        ? ProfileStyles.accent
                        : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            const SizedBox(height: 16),

            // Next / Done button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _next,
                  style: ProfileStyles.primary,
                  child: Text(_isLastPage ? 'Done' : 'Next'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TutorialPage {
  final String title;
  final String description;
  // final String? imagePath; // add later when assets are ready
  const _TutorialPage({required this.title, required this.description});
}

class _TutorialPageContent extends StatelessWidget {
  final _TutorialPage page;
  const _TutorialPageContent({required this.page});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Image placeholder — replace with Image.asset(page.imagePath!) later
          Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              color: ProfileStyles.avatarBg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Center(
              child: Icon(Icons.image, size: 60, color: ProfileStyles.avatarIcon),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            page.title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            page.description,
            style: const TextStyle(fontSize: 16, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

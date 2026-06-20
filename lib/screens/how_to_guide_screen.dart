import 'package:flutter/material.dart';
import '../theme/auth_styles.dart';

/// Entry screen for the in-app step-by-step guide reached from the home
/// `?` icon. Shows three topic cards (Ask / Offer / AI). Tapping a card
/// pushes a [_HowToFlowScreen] that swipes through screenshots + captions
/// for that topic.
class HowToGuideScreen extends StatelessWidget {
  const HowToGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  AuthBackButton(onTap: () => Navigator.pop(context)),
                  const AuthPill('How to use'),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'How to use Help-vrywhere',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: AuthStyles.darkBg,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Pick a topic to see step-by-step instructions.',
                style: TextStyle(
                  fontSize: 14,
                  color: AuthStyles.subtleText,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ListView.separated(
                  itemCount: _topics.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _TopicCard(
                    topic: _topics[i],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => _HowToFlowScreen(topic: _topics[i]),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopicCard extends StatelessWidget {
  final _HowToTopic topic;
  final VoidCallback onTap;
  const _TopicCard({required this.topic, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AuthStyles.cardBorder),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: topic.iconBg,
                shape: BoxShape.circle,
              ),
              child: Icon(topic.icon, color: topic.iconColor, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    topic.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AuthStyles.darkBg,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    topic.subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AuthStyles.subtleText,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                size: 22, color: AuthStyles.subtleText),
          ],
        ),
      ),
    );
  }
}

// ─── Flow viewer ─────────────────────────────────────────────────────────

class _HowToFlowScreen extends StatefulWidget {
  final _HowToTopic topic;
  const _HowToFlowScreen({required this.topic});

  @override
  State<_HowToFlowScreen> createState() => _HowToFlowScreenState();
}

class _HowToFlowScreenState extends State<_HowToFlowScreen> {
  final _pageController = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool get _isLast => _page == widget.topic.steps.length - 1;
  bool get _isFirst => _page == 0;

  void _next() {
    if (_isLast) {
      Navigator.pop(context);
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _previous() {
    if (_isFirst) return;
    _pageController.previousPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.topic.steps.length;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  AuthBackButton(onTap: () => Navigator.pop(context)),
                  AuthPill('${widget.topic.title} · ${_page + 1}/$total'),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: total,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (_, i) {
                    final step = widget.topic.steps[i];
                    return _StepView(step: step);
                  },
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(total, (i) {
                  final active = i == _page;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 20 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: active
                          ? AuthStyles.linkBlue
                          : AuthStyles.cardBorder,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: OutlinedButton(
                        onPressed: _isFirst ? null : _previous,
                        style: AuthStyles.outlinedPill(),
                        child: const Text('Previous'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _next,
                        style: AuthStyles.primaryPill(),
                        child: Text(_isLast ? 'Done' : 'Next'),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepView extends StatelessWidget {
  final _HowToStep step;
  const _StepView({required this.step});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Phone-screenshot frame. Constrained so tall screenshots don't
          // dominate; the caption below stays visible without scrolling
          // on most devices.
          Container(
            constraints: const BoxConstraints(maxHeight: 360),
            decoration: BoxDecoration(
              color: AuthStyles.pillBg,
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.all(8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                step.image,
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            step.title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AuthStyles.darkBg,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            step.caption,
            style: const TextStyle(
              fontSize: 14,
              color: AuthStyles.subtleText,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Data ────────────────────────────────────────────────────────────────

class _HowToStep {
  final String image;
  final String title;
  final String caption;
  const _HowToStep({
    required this.image,
    required this.title,
    required this.caption,
  });
}

class _HowToTopic {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final List<_HowToStep> steps;
  const _HowToTopic({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.steps,
  });
}

const _topics = <_HowToTopic>[
  _HowToTopic(
    title: 'Ask for help',
    subtitle: 'Post a request and have a neighbor come help.',
    icon: Icons.location_on_outlined,
    iconBg: AuthStyles.softBlueBg,
    iconColor: AuthStyles.linkBlue,
    steps: [
      _HowToStep(
        image: 'assets/how-to/ask/01_home.png',
        title: 'Start from the Home screen',
        caption:
            'Start at the Home screen. To create a new help request, tap the blue + button at the bottom center.',
      ),
      _HowToStep(
        image: 'assets/how-to/ask/02_form.png',
        title: 'Fill in your request',
        caption:
            "Fill in the required fields — title, category, description, phone number, and when you'd like the help — then tap Confirm at the bottom.",
      ),
      _HowToStep(
        image: 'assets/how-to/ask/03_my_requests.png',
        title: 'Track your request',
        caption:
            'Your request is now live and visible to nearby neighbors. You can check the progress of your request anytime from the My Requests tab at the bottom of the screen.',
      ),
      _HowToStep(
        image: 'assets/how-to/ask/04_at_door.png',
        title: 'When the helper arrives',
        caption:
            'When a helper reaches your door, this screen pops up with their name and a short trip code (e.g. "SAND · 13"). Ask the helper to tell you the code before you open the door. If it matches, tap Let them in. If it does not, tap Not them.',
      ),
    ],
  ),
  _HowToTopic(
    title: 'Offer help',
    subtitle: 'See requests near you and lend a neighbor a hand.',
    icon: Icons.favorite_outline,
    iconBg: AuthStyles.badgeGreenBg,
    iconColor: AuthStyles.badgeGreenText,
    steps: [
      _HowToStep(
        image: 'assets/how-to/offer/01_home.png',
        title: 'Start from the Home screen',
        caption:
            'From the Home screen, tap "Offer to help nearby" to see what neighbors close to you need a hand with.',
      ),
      _HowToStep(
        image: 'assets/how-to/offer/02_empty_tab.png',
        title: 'Open the volunteer tab',
        caption:
            "The first time you open the map tab, you'll see this welcome screen. Tap View nearby requests to load the requests near you.",
      ),
      _HowToStep(
        image: 'assets/how-to/offer/03_nearby.png',
        title: 'Browse nearby requests',
        caption:
            'The map shows nearby requests as dots, with a scrollable list below sorted by distance. Each card shows the requester, distance, category, and rough walking time. Tap I can help to start helping, or Directions to preview the route.',
      ),
      _HowToStep(
        image: 'assets/how-to/offer/04_detail.png',
        title: 'Read the full request',
        caption:
            "Tapping a request opens its full detail — description, posted time, distance, and any replies so far. A 'Stay safe' reminder appears just above the action buttons. When you're ready, tap Offer help.",
      ),
      _HowToStep(
        image: 'assets/how-to/offer/05_confirm.png',
        title: 'Confirm you can help',
        caption:
            "A short confirm sheet lets you double-check the arrival time (tap Adjust to change it) and distance, and add an optional note for the requester. If you're bringing something, the Suggest with AI button can help draft the note. When you're ready, tap Yes, I'm on my way.",
      ),
      _HowToStep(
        image: 'assets/how-to/offer/06_matched.png',
        title: "You're matched",
        caption:
            "Once matched, you'll see the requester's name and a short trip code. They have already been notified you're on the way. Tap Start navigation when you're ready to head over.",
      ),
      _HowToStep(
        image: 'assets/how-to/offer/07_navigation.png',
        title: 'Follow the navigation',
        caption:
            "Turn-by-turn directions guide you to the requester's location. The bottom bar shows the remaining distance, ETA, and an End button in case you need to stop early.",
      ),
      _HowToStep(
        image: 'assets/how-to/offer/08_arrived.png',
        title: 'At the door',
        caption:
            "When you arrive, this screen shows your trip code. Tell the requester the code so they can match it on their side — it's a small safety check so both of you know you're meeting the right person. Tap I'm at the door to confirm.",
      ),
    ],
  ),
  _HowToTopic(
    title: 'Use the AI helper',
    subtitle: 'Get step-by-step guidance for any task on your phone.',
    icon: Icons.smart_toy_outlined,
    iconBg: AuthStyles.pillBg,
    iconColor: AuthStyles.darkBg,
    steps: [
      _HowToStep(
        image: 'assets/how-to/ai/01_home.png',
        title: 'Start from the Home screen',
        caption:
            'From the Home screen, tap "Ask the AI helper" to get step-by-step guidance on any task on your phone.',
      ),
      _HowToStep(
        image: 'assets/how-to/ai/02_overlay.png',
        title: 'Open the assistant',
        caption:
            "A small assistant appears at the bottom of your screen, ready to listen. Tap the mic icon and say what you want to do — for example, 'help me open YouTube'.",
      ),
      _HowToStep(
        image: 'assets/how-to/ai/03_collapsed.png',
        title: 'Follow the first step',
        caption:
            'The AI looks at your current screen and shows the first step as a small hint at the bottom. Find the matching button on your screen and tap it.',
      ),
      _HowToStep(
        image: 'assets/how-to/ai/04_expanded.png',
        title: 'See full step details',
        caption:
            "Tap the hint to expand it for more detail — it shows exactly what to look for on your screen, with a clear description. When you've done it, tap I did it → Next to move on.",
      ),
      _HowToStep(
        image: 'assets/how-to/ai/05_done.png',
        title: 'Goal reached',
        caption:
            'When you reach your goal, the assistant shows a green Done badge. Tap Close Assistant to dismiss the overlay and return to using your phone normally.',
      ),
    ],
  ),
];

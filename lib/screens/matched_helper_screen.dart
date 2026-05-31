import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_helpvrywhere/models/nearby_request.dart';
import 'package:flutter_application_helpvrywhere/models/trip.dart';
import 'package:flutter_application_helpvrywhere/screens/chat_screen.dart';
import 'package:flutter_application_helpvrywhere/services/conversation_service.dart';
import 'package:flutter_application_helpvrywhere/theme/app_theme.dart';
import 'package:flutter_application_helpvrywhere/widgets/pill_button.dart';

/// Step 2 (helper side) — "You're matched" hero screen shown right
/// after a volunteer confirms in [ConfirmHelpSheet] and the trip is
/// created in Firestore.
///
/// Layout: full dark-navy hero with decorative gradient blobs, a
/// handshake-style avatar pair, the trip code card ("BLU · 47"), and
/// two CTAs at the bottom (Message + Start navigation). Status bar
/// flips to light-on-dark.
///
/// Tapping "Start navigation" pops back with `true` so the caller can
/// kick off the real navigation flow (GPS + route + push of the
/// existing navigation screen). Backing out via the system back leaves
/// the trip in `confirmed` status — the active-request banner on the
/// nearby-requests screen will still surface it.
class MatchedHelperScreen extends StatelessWidget {
  const MatchedHelperScreen({
    super.key,
    required this.request,
    required this.trip,
    required this.helperInitials,
    required this.helperDisplayName,
  });

  final NearbyRequest request;
  final Trip trip;

  /// Initials + name of the currently-signed-in volunteer (the helper).
  /// Passed in rather than read off `FirebaseAuth.currentUser` here so
  /// this screen stays trivially testable.
  final String helperInitials;
  final String helperDisplayName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkNavy,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Stack(
          children: [
            // Decorative gradient blobs (blue top-left, green bottom-right)
            const Positioned(
              left: -90,
              top: -120,
              child: _GradientBlob(
                color: AppColors.primaryBlue,
                size: 300,
                opacity: 0.35,
              ),
            ),
            const Positioned(
              right: -80,
              bottom: -100,
              child: _GradientBlob(
                color: AppColors.primaryGreen,
                size: 280,
                opacity: 0.3,
              ),
            ),

            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top row: home button (preserves the trip; banner
                    // on the map screen surfaces it for later resume).
                    Row(
                      children: [
                        _OnDarkIconButton(
                          icon: Icons.home_rounded,
                          tooltip: 'Back to home',
                          onPressed: () => Navigator.of(context)
                              .popUntil((route) => route.isFirst),
                        ),
                        const Spacer(),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '✦ YOU\'RE MATCHED',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.8,
                        color: AppColors.primaryGreen,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${request.requesterName} is expecting you.',
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.65,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'They have been notified and are at home. Tap navigate when you\'re ready to head over.',
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.white.withOpacity(0.75),
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: 24),

                    Center(
                      child: _Handshake(
                        helperInitials: helperInitials,
                        requesterInitials: request.requesterInitials,
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Names
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(
                        children: [
                          _PersonLabel(
                            name: helperDisplayName,
                            role: 'HELPER',
                            align: TextAlign.left,
                          ),
                          const Spacer(),
                          _PersonLabel(
                            name: request.requesterName,
                            role: 'REQUESTER',
                            align: TextAlign.right,
                          ),
                        ],
                      ),
                    ),

                    const Spacer(),

                    _TripCodeCard(code: trip.code),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: _OnDarkButton(
                            label: 'Message',
                            icon: Icons.chat_bubble_outline_rounded,
                            onPressed: () => _openChat(context),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: PillButton.primary(
                            label: 'Start navigation',
                            icon: Icons.navigation_rounded,
                            height: 52,
                            fontSize: 16,
                            color: AppColors.primaryGreen,
                            onPressed: () =>
                                Navigator.of(context).pop(true),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Opens the chat between the helper and the requester. Creates the
  /// conversation doc lazily if it doesn't already exist (mirrors the
  /// pattern used elsewhere — chats are 1:1 between two uids).
  Future<void> _openChat(BuildContext context) async {
    final convoService = ConversationService();
    final convoId = await convoService.createConversation(
      currentUserId: trip.helperUid,
      otherUserId: trip.requesterUid,
    );
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          conversationId: convoId,
          otherUserId: trip.requesterUid,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Internals
// ─────────────────────────────────────────────────────────────────────

class _GradientBlob extends StatelessWidget {
  const _GradientBlob({
    required this.color,
    required this.size,
    required this.opacity,
  });

  final Color color;
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withOpacity(opacity), color.withOpacity(0)],
            stops: const [0, 0.7],
          ),
        ),
      ),
    );
  }
}

/// Helper avatar (left, with pulsing ring), requester avatar (right),
/// beating heart link in the middle. The animation makes the "match"
/// feel alive rather than static.
class _Handshake extends StatefulWidget {
  const _Handshake({
    required this.helperInitials,
    required this.requesterInitials,
  });

  final String helperInitials;
  final String requesterInitials;

  @override
  State<_Handshake> createState() => _HandshakeState();
}

class _HandshakeState extends State<_Handshake>
    with TickerProviderStateMixin {
  late final AnimationController _beat = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2500),
  )..repeat();

  @override
  void dispose() {
    _beat.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 100,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Helper avatar (left, with pulse ring)
          Transform.translate(
            offset: const Offset(-46, 0),
            child: _BigAvatar(
              initials: widget.helperInitials,
              background: AppColors.primaryBlue,
              foreground: Colors.white,
              pulse: _pulse,
            ),
          ),
          // Requester avatar (right)
          Transform.translate(
            offset: const Offset(46, 0),
            child: _BigAvatar(
              initials: widget.requesterInitials,
              background: Colors.white,
              foreground: AppColors.primaryBlue,
              pulse: null,
            ),
          ),
          // Heart link (center, beats every 1.6 s)
          AnimatedBuilder(
            animation: _beat,
            builder: (ctx, _) {
              final t = _beat.value;
              double scale = 1.0;
              if (t < 0.2) {
                scale = 1.0 + 0.15 * (t / 0.2);
              } else if (t < 0.4) {
                scale = 1.15 - 0.15 * ((t - 0.2) / 0.2);
              } else if (t < 0.6) {
                scale = 1.0 + 0.10 * ((t - 0.4) / 0.2);
              } else if (t < 0.8) {
                scale = 1.10 - 0.10 * ((t - 0.6) / 0.2);
              }
              return Transform.scale(
                scale: scale,
                child: Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.darkNavy, width: 4),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.primaryBlue, AppColors.primaryGreen],
                    ),
                  ),
                  // Handshake — communicates "two people meeting to help
                  // each other" without the dating-app connotation a
                  // heart icon carries.
                  child: const Icon(
                    Icons.handshake_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BigAvatar extends StatelessWidget {
  const _BigAvatar({
    required this.initials,
    required this.background,
    required this.foreground,
    required this.pulse,
  });

  final String initials;
  final Color background;
  final Color foreground;
  final AnimationController? pulse;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 70,
      height: 70,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          if (pulse != null)
            AnimatedBuilder(
              animation: pulse!,
              builder: (ctx, _) {
                final t = pulse!.value;
                final scale = 0.9 + 0.5 * t;
                final opacity = (0.5 - 0.5 * t).clamp(0.0, 0.5);
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: foreground.withOpacity(opacity),
                        width: 2,
                      ),
                    ),
                  ),
                );
              },
            ),
          Container(
            width: 70,
            height: 70,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: background,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withOpacity(0.1),
                width: 4,
              ),
            ),
            child: Text(
              initials,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: foreground,
                letterSpacing: -0.44,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonLabel extends StatelessWidget {
  const _PersonLabel({
    required this.name,
    required this.role,
    required this.align,
  });

  final String name;
  final String role;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    final cross = align == TextAlign.left
        ? CrossAxisAlignment.start
        : CrossAxisAlignment.end;
    return Column(
      crossAxisAlignment: cross,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name,
          textAlign: align,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 15,
            letterSpacing: -0.13,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          role,
          textAlign: align,
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

/// Semi-transparent white-on-dark card showing the trip code with a
/// little decorative color-block art on the right.
class _TripCodeCard extends StatelessWidget {
  const _TripCodeCard({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(AppRadius.tile),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'YOUR TRIP',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  code,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'monospace',
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
              ],
            ),
          ),
          // Tiny color-block art
          Row(
            children: const [
              _CodeBlock(color: AppColors.primaryBlue),
              SizedBox(width: 3),
              _CodeBlock(color: AppColors.primaryGreen),
              SizedBox(width: 3),
              _CodeBlock(color: AppColors.primaryBlue),
              SizedBox(width: 3),
              _CodeBlock(color: Colors.white24),
            ],
          ),
        ],
      ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 22,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

/// Small circular icon button styled for the dark-navy hero. Used
/// for the "back to home" chip in the top-left.
class _OnDarkIconButton extends StatelessWidget {
  const _OnDarkIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Colors.white.withOpacity(0.1),
      shape: CircleBorder(
        side: BorderSide(color: Colors.white.withOpacity(0.18), width: 1),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 18, color: Colors.white),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// Pill button styled for the dark-navy background (10% white fill,
/// 18% white border). Mirrors the design's `PillButton.onDark`.
class _OnDarkButton extends StatelessWidget {
  const _OnDarkButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Material(
        color: Colors.white.withOpacity(0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          side: BorderSide(color: Colors.white.withOpacity(0.18), width: 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

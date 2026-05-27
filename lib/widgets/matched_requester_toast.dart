import 'package:flutter/material.dart';
import 'package:flutter_application_helpvrywhere/models/trip.dart';
import 'package:flutter_application_helpvrywhere/screens/chat_screen.dart';
import 'package:flutter_application_helpvrywhere/services/conversation_service.dart';
import 'package:flutter_application_helpvrywhere/services/user_service.dart';
import 'package:flutter_application_helpvrywhere/theme/app_theme.dart';
import 'package:flutter_application_helpvrywhere/widgets/pill_button.dart';

/// Step 2 (requester side) — the rich card the requester sees on their
/// own request right after a helper confirms in [ConfirmHelpSheet].
///
/// Shown at the top of [RequestDetailScreen] when the request belongs
/// to the current user AND a corresponding [Trip] exists. Streams the
/// trip doc so the card stays accurate as the helper's ETA / bring
/// list updates.
///
/// Layout (matches handoff):
///   • Pulsing green heart in a light-green circle on the left
///   • "✦ HELP ON THE WAY" eyebrow (green)
///   • "{Helper name} can help" title
///   • Sub: "They'll arrive in about **N min**." + optional note
///   • Action row: "View trip" dark pill + "Message" outlined pill
class MatchedRequesterToast extends StatefulWidget {
  const MatchedRequesterToast({
    super.key,
    required this.trip,
    this.onViewTrip,
    this.margin = const EdgeInsets.fromLTRB(16, 12, 16, 0),
  });

  final Trip trip;

  /// Optional override for the "View trip" action — if null, taps
  /// will surface a SnackBar (the live tracking screen is wired in a
  /// future phase).
  final VoidCallback? onViewTrip;

  /// Outer margin. Defaults to the same gutter we use inside a
  /// `ListView`. Pass `EdgeInsets.zero` when nesting inside a parent
  /// that already provides its own padding (e.g. the home tab).
  final EdgeInsets margin;

  @override
  State<MatchedRequesterToast> createState() => _MatchedRequesterToastState();
}

class _MatchedRequesterToastState extends State<MatchedRequesterToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2500),
  )..repeat();

  /// Helper's display name — looked up on first build from the users
  /// collection so the toast can render a friendly "Margaret K. can
  /// help" instead of "Helper can help".
  String _helperName = 'Your helper';
  bool _nameLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadHelperName();
  }

  Future<void> _loadHelperName() async {
    try {
      final name = await UserService().getUsername(widget.trip.helperUid);
      if (!mounted) return;
      setState(() {
        _helperName = (name.isEmpty || name == 'Unknown')
            ? 'Your helper'
            : name;
        _nameLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _nameLoaded = true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    final note = trip.helperNote.trim();
    final checkedBringing = trip.bringList
        .where((i) => i.checked && i.label.isNotEmpty)
        .map((i) => i.label)
        .toList();

    return Container(
      margin: widget.margin,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Pulsing green helping-hands icon
              SizedBox(
                width: 46,
                height: 46,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _pulse,
                      builder: (ctx, _) {
                        final t = _pulse.value;
                        final scale = 0.9 + 0.5 * t;
                        final op = (0.5 - 0.5 * t).clamp(0.0, 0.5);
                        return Transform.scale(
                          scale: scale,
                          child: Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.primaryGreen.withOpacity(op),
                            ),
                          ),
                        );
                      },
                    ),
                    Container(
                      width: 46,
                      height: 46,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.lightGreen,
                      ),
                      child: const Icon(
                        Icons.volunteer_activism_rounded,
                        color: AppColors.primaryGreen,
                        size: 22,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '✦ HELP ON THE WAY',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: AppColors.primaryGreen,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _nameLoaded ? '$_helperName can help' : 'A helper is on the way',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.darkNavy,
                        letterSpacing: -0.13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text.rich(
                      TextSpan(
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.muted,
                          height: 1.45,
                        ),
                        children: [
                          const TextSpan(text: "They'll arrive in about "),
                          TextSpan(
                            text: '${trip.etaMinutes} min',
                            style: const TextStyle(
                              color: AppColors.darkNavy,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const TextSpan(text: '. '),
                          if (checkedBringing.isNotEmpty)
                            TextSpan(
                              text:
                                  "They'll bring ${checkedBringing.first.toLowerCase()}.",
                            ),
                        ],
                      ),
                    ),
                    if (note.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.lightGreen,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '“$note”',
                          style: const TextStyle(
                            fontSize: 14,
                            fontStyle: FontStyle.italic,
                            color: AppColors.safetyText,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Trip code line — monospace, lets the requester read it
          // back when the helper arrives at the door.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F6F8),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.qr_code_rounded,
                    size: 18, color: AppColors.muted),
                const SizedBox(width: 8),
                Text(
                  'Trip ${trip.code}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                    color: AppColors.darkNavy,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: PillButton.primary(
                  label: 'View trip',
                  icon: Icons.near_me_rounded,
                  height: 46,
                  fontSize: 15,
                  color: AppColors.darkNavy,
                  onPressed: widget.onViewTrip ??
                      () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Live tracking coming next.'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PillButton.outline(
                  label: 'Message',
                  icon: Icons.chat_bubble_outline_rounded,
                  height: 46,
                  fontSize: 15,
                  onPressed: () => _openChat(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openChat(BuildContext context) async {
    final convo = await ConversationService().createConversation(
      currentUserId: widget.trip.requesterUid,
      otherUserId: widget.trip.helperUid,
    );
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          conversationId: convo,
          otherUserId: widget.trip.helperUid,
        ),
      ),
    );
  }
}

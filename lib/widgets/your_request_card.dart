import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_helpvrywhere/models/request_model.dart';
import 'package:flutter_application_helpvrywhere/screens/request_detail_screen.dart';
import 'package:flutter_application_helpvrywhere/services/viewer_presence_service.dart';
import 'package:flutter_application_helpvrywhere/theme/app_theme.dart';

/// "Your request" spotlight card for the My Requests tab.
///
/// Renders a single [request] (the tab picks the most-recent **open**
/// one and passes it in — it already streams the user's requests, so
/// the card doesn't re-stream) with:
///   • Header: "Your request" + a pulsing "LIVE" badge + an overflow
///     (⋮) menu for owner actions (edit / mark done / cancel / delete),
///     shown when the matching callbacks are supplied
///   • Title (the request title)
///   • "Posted Xm ago" subtitle
///   • Pill: blue pulse dot + "N neighbours are checking" — wired to
///     [ViewerPresenceService] so it updates in real time as helpers
///     open/close the detail screen. Switches to "A helper accepted
///     your request" once the request is accepted.
///
/// Tapping the card opens the request detail screen.
class YourRequestCard extends StatelessWidget {
  const YourRequestCard({
    super.key,
    required this.request,
    this.onEdit,
    this.onComplete,
    this.onCancel,
    this.onDelete,
  });

  final RequestModel request;

  /// Owner actions, surfaced through the header overflow (⋮) menu. Each
  /// item is shown only when its callback is non-null, so the My Requests
  /// tab owns the policy:
  ///   • [onEdit] — passed only for *active* requests (editing resets a
  ///     request to active, so it shouldn't be offered once a helper has
  ///     accepted, or it would silently un-accept it).
  ///   • [onComplete] / [onCancel] — passed while the request is open.
  ///   • [onDelete] — always available (the tab wraps it in a confirm
  ///     dialog first, since deleting can't be undone).
  /// When all four are null the menu is hidden entirely.
  final VoidCallback? onEdit;
  final VoidCallback? onComplete;
  final VoidCallback? onCancel;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return _CardBody(
      request: request,
      currentUid: uid,
      onEdit: onEdit,
      onComplete: onComplete,
      onCancel: onCancel,
      onDelete: onDelete,
    );
  }
}

class _CardBody extends StatelessWidget {
  const _CardBody({
    required this.request,
    required this.currentUid,
    this.onEdit,
    this.onComplete,
    this.onCancel,
    this.onDelete,
  });

  final RequestModel request;
  final String currentUid;
  final VoidCallback? onEdit;
  final VoidCallback? onComplete;
  final VoidCallback? onCancel;
  final VoidCallback? onDelete;

  bool get _hasMenu =>
      onEdit != null ||
      onComplete != null ||
      onCancel != null ||
      onDelete != null;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: () =>
            RequestDetailScreen.openForModel(context, request),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppRadius.card),
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
              // Header — "Your request" + LIVE badge
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Your request',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.darkNavy,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  _LiveBadge(),
                  if (_hasMenu) ...[
                    const SizedBox(width: 4),
                    _OwnerMenu(
                      onEdit: onEdit,
                      onComplete: onComplete,
                      onCancel: onCancel,
                      onDelete: onDelete,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),

              // Title
              Text(
                request.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.darkNavy,
                  letterSpacing: -0.2,
                  height: 1.25,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),

              // Subtitle — posted Xm ago
              Text(
                'Posted ${_relativeTime(request.createdAt)}',
                style: const TextStyle(
                  fontSize: 13.5,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w500,
                ),
              ),

              const SizedBox(height: 14),

              // Live presence pill — "N neighbours are checking"
              _CheckingPill(
                requestId: request.id,
                excludeUid: currentUid,
                requestStatus: request.status,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pill that subscribes to [ViewerPresenceService.watchActiveViewerCount]
/// and renders "{N} neighbours are checking" with a pulsing blue dot.
/// Hidden entirely when count is zero so the card doesn't show a
/// placeholder during quiet periods.
class _CheckingPill extends StatefulWidget {
  const _CheckingPill({
    required this.requestId,
    required this.excludeUid,
    required this.requestStatus,
  });

  final String requestId;
  final String excludeUid;
  final RequestStatus requestStatus;

  @override
  State<_CheckingPill> createState() => _CheckingPillState();
}

class _CheckingPillState extends State<_CheckingPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Once a request is accepted, the helper is known and no other
    // "neighbours are checking" — show a different pill instead.
    if (widget.requestStatus == RequestStatus.accepted) {
      return _StaticPill(
        background: AppColors.lightGreen,
        foreground: AppColors.primaryGreen,
        icon: Icons.volunteer_activism_rounded,
        label: 'A helper accepted your request',
      );
    }

    return StreamBuilder<int>(
      stream: ViewerPresenceService().watchActiveViewerCount(
        widget.requestId,
        excludeUid: widget.excludeUid,
      ),
      builder: (ctx, snap) {
        final count = snap.data ?? 0;
        if (count == 0) {
          return _StaticPill(
            background: AppColors.lightBlue,
            foreground: AppColors.primaryBlue,
            icon: Icons.visibility_outlined,
            label: 'No one is checking right now',
          );
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.lightBlue,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Row(
            children: [
              // Pulsing blue dot — telegraphs "live".
              SizedBox(
                width: 12,
                height: 12,
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (ctx, _) {
                    final t = _pulse.value;
                    final ringScale = 1.0 + 1.8 * t;
                    final ringOpacity = (0.5 - 0.5 * t).clamp(0.0, 0.5);
                    return Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        Transform.scale(
                          scale: ringScale,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.primaryBlue
                                  .withOpacity(ringOpacity),
                            ),
                          ),
                        ),
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.primaryBlue,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  count == 1
                      ? '1 neighbour is checking'
                      : '$count neighbours are checking',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryBlue,
                    letterSpacing: -0.13,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Live "LIVE" badge with a tiny pulsing red dot — shown on the
/// header row to emphasise the card is real-time.
class _LiveBadge extends StatefulWidget {
  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _ctrl,
          builder: (ctx, _) {
            final op = 0.4 + 0.6 * _ctrl.value;
            return Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFEF4444).withOpacity(op),
              ),
            );
          },
        ),
        const SizedBox(width: 6),
        const Text(
          'LIVE',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: AppColors.muted,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

/// Header overflow (⋮) menu exposing the owner's actions on their own
/// request — edit, mark done, cancel, delete. Each item appears only
/// when the matching callback is non-null (the My Requests tab gates
/// them by request status), and the menu itself is only mounted when at
/// least one action applies.
class _OwnerMenu extends StatelessWidget {
  const _OwnerMenu({
    this.onEdit,
    this.onComplete,
    this.onCancel,
    this.onDelete,
  });

  final VoidCallback? onEdit;
  final VoidCallback? onComplete;
  final VoidCallback? onCancel;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: AppColors.muted),
      tooltip: 'Manage request',
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      onSelected: (v) {
        switch (v) {
          case 'edit':
            onEdit?.call();
          case 'complete':
            onComplete?.call();
          case 'cancel':
            onCancel?.call();
          case 'delete':
            onDelete?.call();
        }
      },
      itemBuilder: (_) => [
        if (onEdit != null)
          const PopupMenuItem(
            value: 'edit',
            child: _MenuRow(Icons.edit_outlined, 'Edit'),
          ),
        if (onComplete != null)
          const PopupMenuItem(
            value: 'complete',
            child: _MenuRow(Icons.check_circle_outline_rounded, 'Mark done'),
          ),
        if (onCancel != null)
          const PopupMenuItem(
            value: 'cancel',
            child: _MenuRow(Icons.cancel_outlined, 'Cancel'),
          ),
        if (onDelete != null)
          const PopupMenuItem(
            value: 'delete',
            child: _MenuRow(Icons.delete_outline_rounded, 'Delete',
                danger: true),
          ),
      ],
    );
  }
}

/// Single row inside [_OwnerMenu] — icon + label, tinted red for the
/// destructive [danger] action.
class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.label, {this.danger = false});

  final IconData icon;
  final String label;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? Colors.red : AppColors.darkNavy;
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// Inert pill used for fallback states ("no one is checking", "a
/// helper accepted"). Same shape as the live pill so the card layout
/// doesn't shift when state changes.
class _StaticPill extends StatelessWidget {
  const _StaticPill({
    required this.background,
    required this.foreground,
    required this.icon,
    required this.label,
  });

  final Color background;
  final Color foreground;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: foreground),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: foreground,
                letterSpacing: -0.13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "5m ago" / "2h ago" / "3d ago" / "just now". Compact relative-time
/// stamp for the card's "Posted X ago" subtitle.
String _relativeTime(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

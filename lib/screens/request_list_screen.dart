import 'package:flutter/material.dart';
import '../models/request_model.dart';
import '../services/auth_service.dart';
import '../services/request_service.dart';
import '../theme/app_theme.dart';
import '../widgets/your_request_card.dart';
import 'request_detail_screen.dart';
import 'request_edit_screen.dart';

/// The "My Requests" tab body.
///
/// Streams the signed-in user's requests once and lays them out as:
///   • A compact stat summary (Waiting / Accepted / Done / Cancelled).
///   • A live **spotlight** — the most-recent *open* request, rendered
///     with [YourRequestCard] so the requester sees the real-time
///     "N neighbours are checking" presence count + LIVE badge.
///   • A clean list of every other request, each opening the detail
///     screen on tap with a tidy overflow menu for edit / complete /
///     cancel / delete (replacing the old cramped 4-icon row).
class RequestListWidget extends StatelessWidget {
  const RequestListWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final service = RequestService();
    final user = AuthService().currentUser;

    if (user == null) {
      return const Center(child: Text('Not logged in'));
    }

    return StreamBuilder<List<RequestModel>>(
      stream: service.getUserRequests(user.uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(child: Text('Error loading requests'));
        }

        final all = snapshot.data ?? const <RequestModel>[];
        if (all.isEmpty) return const _EmptyMyRequests();

        // Spotlight = most-recent OPEN (active or accepted) request.
        final open = all
            .where((r) =>
                r.status == RequestStatus.active ||
                r.status == RequestStatus.accepted)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        final spotlight = open.isNotEmpty ? open.first : null;

        // Everything else — exclude the spotlight so it isn't shown
        // twice. Sort most-actionable first, then most-recent.
        final rest = all.where((r) => r.id != spotlight?.id).toList()
          ..sort((a, b) {
            final p = _priority(a.status).compareTo(_priority(b.status));
            return p != 0 ? p : b.createdAt.compareTo(a.createdAt);
          });

        return ListView(
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            _StatSummary(requests: all),
            const SizedBox(height: 18),

            if (spotlight != null) ...[
              YourRequestCard(
                request: spotlight,
                // Editing resets the request to active, so only offer it
                // while the request is still waiting — not once a helper
                // has accepted (that would silently un-accept it and
                // desync the helper's trip).
                onEdit: spotlight.status == RequestStatus.active
                    ? () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                RequestEditScreen(request: spotlight),
                          ),
                        )
                    : null,
                // The spotlight is always an open request, so mark-done /
                // cancel always apply. Delete is confirmed first (the same
                // dialog the tiles below use) because it can't be undone.
                onComplete: () => service.updateStatus(
                    spotlight.id, RequestStatus.completed),
                onCancel: () => service.updateStatus(
                    spotlight.id, RequestStatus.cancelled),
                onDelete: () => _confirmDelete(
                    context, () => service.deleteRequest(spotlight.id)),
              ),
              const SizedBox(height: 20),
            ],

            if (rest.isNotEmpty) ...[
              Text(
                spotlight == null ? 'Your requests' : 'Earlier requests',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.darkNavy,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 10),
              for (final r in rest)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _RequestTile(
                    request: r,
                    onOpen: () =>
                        RequestDetailScreen.openForModel(context, r),
                    onEdit: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RequestEditScreen(request: r),
                      ),
                    ),
                    onComplete: () => service.updateStatus(
                        r.id, RequestStatus.completed),
                    onCancel: () => service.updateStatus(
                        r.id, RequestStatus.cancelled),
                    onDelete: () => service.deleteRequest(r.id),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Stat summary row
// ---------------------------------------------------------------------------

class _StatSummary extends StatelessWidget {
  const _StatSummary({required this.requests});

  final List<RequestModel> requests;

  int _count(RequestStatus s) =>
      requests.where((r) => r.status == s).length;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          _Stat(
            label: 'Waiting',
            value: _count(RequestStatus.active),
            color: const Color(0xFFB45309),
          ),
          const _StatDivider(),
          _Stat(
            label: 'Accepted',
            value: _count(RequestStatus.accepted),
            color: AppColors.primaryBlue,
          ),
          const _StatDivider(),
          _Stat(
            label: 'Done',
            value: _count(RequestStatus.completed),
            color: AppColors.primaryGreen,
          ),
          const _StatDivider(),
          _Stat(
            label: 'Cancelled',
            value: _count(RequestStatus.cancelled),
            color: AppColors.muted,
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$value',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 32, color: AppColors.border);
  }
}

// ---------------------------------------------------------------------------
// Individual request tile (non-spotlight)
// ---------------------------------------------------------------------------

class _RequestTile extends StatelessWidget {
  const _RequestTile({
    required this.request,
    required this.onOpen,
    required this.onEdit,
    required this.onComplete,
    required this.onCancel,
    required this.onDelete,
  });

  final RequestModel request;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onComplete;
  final VoidCallback onCancel;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final chip = _statusStyle(request.status);
    final isOpen = request.status == RequestStatus.active ||
        request.status == RequestStatus.accepted;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.tile),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.tile),
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppRadius.tile),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            request.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.darkNavy,
                              letterSpacing: -0.15,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _StatusChip(style: chip),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${request.category} · Posted ${_relativeTime(request.createdAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: AppColors.muted),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onSelected: (v) {
                  switch (v) {
                    case 'open':
                      onOpen();
                    case 'edit':
                      onEdit();
                    case 'complete':
                      onComplete();
                    case 'cancel':
                      onCancel();
                    case 'delete':
                      _confirmDelete(context, onDelete);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'open',
                    child: _MenuRow(Icons.open_in_new_rounded, 'Open'),
                  ),
                  if (request.status == RequestStatus.active)
                    const PopupMenuItem(
                      value: 'edit',
                      child: _MenuRow(Icons.edit_outlined, 'Edit'),
                    ),
                  if (isOpen) ...[
                    const PopupMenuItem(
                      value: 'complete',
                      child: _MenuRow(
                          Icons.check_circle_outline_rounded, 'Mark done'),
                    ),
                    const PopupMenuItem(
                      value: 'cancel',
                      child: _MenuRow(Icons.cancel_outlined, 'Cancel'),
                    ),
                  ],
                  const PopupMenuItem(
                    value: 'delete',
                    child: _MenuRow(Icons.delete_outline_rounded, 'Delete',
                        danger: true),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Confirms before the destructive delete (the old list deleted with a
/// single tap — easy to fire by accident).
Future<void> _confirmDelete(BuildContext context, VoidCallback onDelete) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete request?'),
      content: const Text(
        'This permanently removes the request. This can’t be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Keep'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
  if (ok == true) onDelete();
}

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

// ---------------------------------------------------------------------------
// Status chip + helpers
// ---------------------------------------------------------------------------

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.style});

  final _ChipStyle style;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: style.bg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        style.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: style.fg,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _ChipStyle {
  const _ChipStyle(this.label, this.fg, this.bg);
  final String label;
  final Color fg;
  final Color bg;
}

_ChipStyle _statusStyle(RequestStatus status) {
  switch (status) {
    case RequestStatus.active:
      return const _ChipStyle(
          'WAITING', Color(0xFFB45309), Color(0xFFFFF7E6));
    case RequestStatus.accepted:
      return const _ChipStyle(
          'ACCEPTED', AppColors.primaryBlue, AppColors.lightBlue);
    case RequestStatus.completed:
      return const _ChipStyle(
          'DONE', AppColors.primaryGreen, AppColors.lightGreen);
    case RequestStatus.cancelled:
      return const _ChipStyle(
          'CANCELLED', AppColors.muted, Color(0xFFF3F4F6));
  }
}

/// Lower = shown first: active → accepted → completed → cancelled.
int _priority(RequestStatus status) {
  switch (status) {
    case RequestStatus.active:
      return 0;
    case RequestStatus.accepted:
      return 1;
    case RequestStatus.completed:
      return 2;
    case RequestStatus.cancelled:
      return 3;
  }
}

/// "just now" / "5m ago" / "2h ago" / "3d ago".
String _relativeTime(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyMyRequests extends StatelessWidget {
  const _EmptyMyRequests();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.lightBlue,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.inbox_rounded,
                  size: 30, color: AppColors.primaryBlue),
            ),
            const SizedBox(height: 16),
            const Text(
              'No requests yet',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.darkNavy,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tap the + button to ask a neighbour for help. '
              'Your requests will show up here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

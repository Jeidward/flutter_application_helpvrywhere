import 'package:flutter/material.dart';
import 'package:flutter_application_helpvrywhere/models/nearby_request.dart';
import 'package:flutter_application_helpvrywhere/screens/request_directions_screen.dart';

/// Read-only detail view for a single nearby request.
class RequestDetailScreen extends StatelessWidget {
  const RequestDetailScreen({super.key, required this.request});

  final NearbyRequest request;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        title: const Text(
          'Request details',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              // TODO(you): handle report / share actions.
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'report', child: Text('Report request')),
              PopupMenuItem(value: 'share', child: Text('Share')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          _RequesterHeader(request: request),
          const SizedBox(height: 20),
          Text(
            request.title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827),
              height: 1.25,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            request.description,
            style: const TextStyle(
              fontSize: 15.5,
              height: 1.5,
              color: Color(0xFF374151),
            ),
          ),
          const SizedBox(height: 24),
          _DetailCard(
            children: [
              _DetailRow(label: 'Category', value: request.category.label),
              const _DetailDivider(),
              _DetailRow(
                label: 'Posted',
                value: _timeAgoLong(request.postedAt),
              ),
              const _DetailDivider(),
              _DetailRow(
                label: 'Estimated time',
                value: '~${request.estimatedMinutes} min',
              ),
              const _DetailDivider(),
              _DetailRow(
                label: 'Distance',
                value: '${request.distanceKm.toStringAsFixed(1)} km',
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SafetyNotice(),
        ],
      ),
      bottomNavigationBar: _BottomActions(
        onHelp: () {
          // TODO(you): accept-request flow.
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('You offered help for "${request.title}"')),
          );
        },
        onDirections: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RequestDirectionsScreen(request: request),
          ),
        ),
      ),
    );
  }
}

/// Builds the requester subtitle line. Handles two real-data quirks:
///   • `neighborhood` may be null when the requester used GPS instead of
///     typing an address.
///   • `distanceKm` is 0 when the volunteer's location isn't available yet.
String _subtitleFor(NearbyRequest r) {
  final parts = <String>[];
  final n = r.neighborhood?.trim();
  if (n != null && n.isNotEmpty) parts.add(n);
  if (r.distanceKm > 0) {
    parts.add('${r.distanceKm.toStringAsFixed(1)} km away');
  }
  if (parts.isEmpty) return 'Nearby';
  return parts.join(' · ');
}

class _RequesterHeader extends StatelessWidget {
  const _RequesterHeader({required this.request});

  final NearbyRequest request;

  @override
  Widget build(BuildContext context) {
    final initials = request.requesterName
        .split(' ')
        .where((p) => p.isNotEmpty)
        .map((p) => p[0])
        .take(2)
        .join();

    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0xFFF3D9CE),
            shape: BoxShape.circle,
          ),
          child: Text(
            initials.toUpperCase(),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFFB14322),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                request.requesterName,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _subtitleFor(request),
                style: const TextStyle(
                  fontSize: 13.5,
                  color: Color(0xFF6B7280),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE3E6EB)),
      ),
      child: Column(children: children),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF111827),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailDivider extends StatelessWidget {
  const _DetailDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, color: Color(0xFFEFF1F4));
  }
}

class _SafetyNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFCE7B5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Icon(Icons.shield_outlined, size: 20, color: Color(0xFFB45309)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Meet in public, share your live location with someone you trust, '
              'and never share financial information.',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: Color(0xFF92400E),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomActions extends StatelessWidget {
  const _BottomActions({required this.onHelp, required this.onDirections});

  final VoidCallback onHelp;
  final VoidCallback onDirections;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE3E6EB))),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4A90E2),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onPressed: onHelp,
                child: const Text('Offer help'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1F2937),
                  side: const BorderSide(color: Color(0xFFD1D5DB)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: onDirections,
                icon: const Icon(Icons.directions, size: 18),
                label: const Text('Directions'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _timeAgoLong(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} minutes ago';
  if (diff.inHours < 24) {
    final h = diff.inHours;
    return '$h ${h == 1 ? "hour" : "hours"} ago';
  }
  final d = diff.inDays;
  return '$d ${d == 1 ? "day" : "days"} ago';
}

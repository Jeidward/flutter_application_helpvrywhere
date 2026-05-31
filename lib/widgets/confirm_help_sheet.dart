import 'package:flutter/material.dart';
import 'package:flutter_application_helpvrywhere/models/nearby_request.dart';
import 'package:flutter_application_helpvrywhere/models/trip.dart';
import 'package:flutter_application_helpvrywhere/theme/app_theme.dart';
import 'package:flutter_application_helpvrywhere/widgets/pill_button.dart';

/// Step 1 of the "Help on the way" flow — modal bottom sheet that asks
/// the volunteer to confirm before the request is atomically claimed.
///
/// Shows a recap of arrival ETA, distance, an editable "what you're
/// bringing" checklist (with optional AI suggestions), and a free-text
/// note that travels with the trip and is shown to the requester.
///
/// Returns a [HelpCommitment] when the volunteer taps "Yes, I'm on my
/// way", or `null` if they back out / dismiss. The caller is
/// responsible for then calling
/// [RequestService.acceptRequest] + [TripService.createForAcceptedRequest].
class ConfirmHelpSheet extends StatefulWidget {
  const ConfirmHelpSheet({
    super.key,
    required this.request,
    this.onRequestAiSuggestions,
  });

  final NearbyRequest request;

  /// Optional AI hook. If provided, tapping "Suggest with AI" calls
  /// this and renders the first returned suggestion in the dashed AI
  /// row inside the checklist card. Wire it to your existing
  /// `AiService` to enable; pass `null` to keep the button as a stub
  /// (it'll just spin and do nothing visible).
  final Future<List<String>> Function(NearbyRequest request)?
      onRequestAiSuggestions;

  /// One-line entry point used by callers. Wraps `showModalBottomSheet`
  /// with the right transparent background + dark scrim so the sheet
  /// sits cleanly over a faded request-detail screen behind it.
  static Future<HelpCommitment?> show(
    BuildContext context, {
    required NearbyRequest request,
    Future<List<String>> Function(NearbyRequest)? onRequestAiSuggestions,
  }) {
    return showModalBottomSheet<HelpCommitment>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.darkNavy.withOpacity(0.4),
      builder: (_) => ConfirmHelpSheet(
        request: request,
        onRequestAiSuggestions: onRequestAiSuggestions,
      ),
    );
  }

  @override
  State<ConfirmHelpSheet> createState() => _ConfirmHelpSheetState();
}

/// Data returned by [ConfirmHelpSheet] on a successful confirm. The
/// caller turns this into Firestore fields on the new trip doc.
class HelpCommitment {
  HelpCommitment({
    required this.etaMinutes,
    required this.items,
    required this.helperNote,
  });

  final int etaMinutes;
  final List<BringItem> items;
  final String helperNote;
}

class _ConfirmHelpSheetState extends State<ConfirmHelpSheet> {
  // ETA starts from the request's estimated walking-time, but the
  // helper can adjust it via the "Adjust" affordance.
  late int _etaMinutes = widget.request.estimatedMinutes;

  // Seed the checklist with one neutral pre-checked item so the user
  // immediately sees the pattern. They can uncheck or replace it.
  late final List<BringItem> _items = <BringItem>[
    BringItem(label: 'I can be there in $_etaMinutes min', checked: true),
  ];

  final _noteCtrl = TextEditingController();

  /// Most recent AI suggestion (or null if none / dismissed). Showing
  /// only the first one keeps the sheet compact; users can tap "Suggest
  /// with AI" again to roll for another.
  String? _aiSuggestion;
  bool _loadingAi = false;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _askAi() async {
    final fn = widget.onRequestAiSuggestions;
    if (fn == null) {
      // No AI hook wired — surface a quick hint so the user isn't
      // left wondering why the chip does nothing.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('AI suggestions not configured yet.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    setState(() => _loadingAi = true);
    try {
      final results = await fn(widget.request);
      if (!mounted) return;
      setState(() {
        _aiSuggestion = results.isNotEmpty ? results.first : null;
      });
    } finally {
      if (mounted) setState(() => _loadingAi = false);
    }
  }

  void _addSuggestion() {
    final s = _aiSuggestion;
    if (s == null) return;
    setState(() {
      _items.add(BringItem(label: s, checked: true, fromAi: true));
      _aiSuggestion = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final requesterName = widget.request.requesterName;
    return SafeArea(
      top: false,
      child: Container(
        margin: EdgeInsets.only(top: MediaQuery.of(context).viewInsets.top),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
        ),
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          18 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppColors.handleGray,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'Confirm you can help',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.17,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'A quick check — $requesterName will see this exactly as you set it.',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.muted,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 14),

              // ARRIVING IN
              _MetaRow(
                iconBg: AppColors.lightBlue,
                iconColor: AppColors.primaryBlue,
                icon: Icons.access_time_rounded,
                label: 'ARRIVING IN',
                value: '~ $_etaMinutes min',
                trailing: GestureDetector(
                  onTap: _adjustEta,
                  child: const Text(
                    'Adjust',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.primaryBlue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // DISTANCE
              _MetaRow(
                iconBg: AppColors.lightGreen,
                iconColor: AppColors.primaryGreen,
                icon: Icons.compare_arrows_rounded,
                label: 'DISTANCE',
                value: widget.request.distanceLabel,
              ),
              const SizedBox(height: 10),

              _ChecklistCard(
                items: _items,
                aiSuggestion: _aiSuggestion,
                loadingAi: _loadingAi,
                noteController: _noteCtrl,
                requesterName: requesterName,
                onToggleItem: (i) => setState(() {
                  _items[i] =
                      _items[i].copyWith(checked: !_items[i].checked);
                }),
                onSuggestAi: _askAi,
                onAddSuggestion: _addSuggestion,
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    flex: 10,
                    child: PillButton.outline(
                      label: 'Back out',
                      height: 52,
                      fontSize: 16,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 14,
                    child: PillButton.primary(
                      label: "Yes, I'm on my way",
                      icon: Icons.handshake_rounded,
                      height: 52,
                      fontSize: 16,
                      onPressed: () => Navigator.of(context).pop(
                        HelpCommitment(
                          etaMinutes: _etaMinutes,
                          items: List.unmodifiable(_items),
                          helperNote: _noteCtrl.text.trim(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _adjustEta() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [10, 15, 20, 30, 45, 60]
              .map(
                (m) => ListTile(
                  title: Text('$m min'),
                  trailing: m == _etaMinutes
                      ? const Icon(Icons.check,
                          color: AppColors.primaryGreen)
                      : null,
                  onTap: () => Navigator.of(ctx).pop(m),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (picked != null) setState(() => _etaMinutes = picked);
  }
}

// ─────────────────────────────────────────────────────────────────────
// Private composition widgets — kept in this file because they're only
// used by ConfirmHelpSheet.
// ─────────────────────────────────────────────────────────────────────

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.iconBg,
    required this.iconColor,
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
  });

  final Color iconBg;
  final Color iconColor;
  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 17, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.darkNavy,
                    letterSpacing: -0.13,
                  ),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _ChecklistCard extends StatelessWidget {
  const _ChecklistCard({
    required this.items,
    required this.aiSuggestion,
    required this.loadingAi,
    required this.noteController,
    required this.requesterName,
    required this.onToggleItem,
    required this.onSuggestAi,
    required this.onAddSuggestion,
  });

  final List<BringItem> items;
  final String? aiSuggestion;
  final bool loadingAi;
  final TextEditingController noteController;
  final String requesterName;
  final void Function(int) onToggleItem;
  final VoidCallback onSuggestAi;
  final VoidCallback onAddSuggestion;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Head row
          Row(
            children: [
              const Expanded(
                child: Text(
                  "WHAT YOU'RE BRINGING",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: AppColors.muted,
                  ),
                ),
              ),
              _AiSuggestChip(onPressed: onSuggestAi, loading: loadingAi),
            ],
          ),
          const SizedBox(height: 8),

          // Items
          for (var i = 0; i < items.length; i++)
            _ChecklistItem(item: items[i], onTap: () => onToggleItem(i)),

          // AI suggestion row
          if (aiSuggestion != null) ...[
            const SizedBox(height: 8),
            const _DashedDivider(),
            const SizedBox(height: 8),
            _AiSuggestionRow(text: aiSuggestion!, onAdd: onAddSuggestion),
          ],

          // Comment field
          const SizedBox(height: 10),
          const _DashedDivider(),
          const SizedBox(height: 10),
          RichText(
            text: TextSpan(
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: AppColors.muted,
              ),
              children: [
                TextSpan(
                    text: 'NOTE FOR ${requesterName.toUpperCase()} '),
                const TextSpan(
                  text: '— optional',
                  style: TextStyle(
                    color: AppColors.placeholder,
                    letterSpacing: 0,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: noteController,
            minLines: 2,
            maxLines: 4,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.darkNavy,
              height: 1.45,
            ),
            decoration: InputDecoration(
              hintText:
                  "e.g. I'll bring a 9W warm-white bulb. Buzz #1421 when I'm at the door.",
              hintStyle: const TextStyle(
                fontSize: 14,
                color: AppColors.placeholder,
                fontWeight: FontWeight.w500,
                height: 1.45,
              ),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.input),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.input),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.input),
                borderSide: const BorderSide(
                  color: AppColors.primaryBlue,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AiSuggestChip extends StatelessWidget {
  const _AiSuggestChip({required this.onPressed, required this.loading});

  final VoidCallback onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onPressed,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primaryBlue, AppColors.indigoBlend],
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            else
              const Icon(Icons.auto_awesome, size: 13, color: Colors.white),
            const SizedBox(width: 5),
            const Text(
              'Suggest with AI',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -0.05,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChecklistItem extends StatelessWidget {
  const _ChecklistItem({required this.item, required this.onTap});

  final BringItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color:
                    item.checked ? AppColors.primaryGreen : Colors.white,
                border: item.checked
                    ? null
                    : Border.all(color: AppColors.border, width: 1.5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: item.checked
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.label,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.darkNavy,
                  height: 1.4,
                ),
              ),
            ),
            if (item.fromAi)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.lightBlue,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: const Text(
                  'AI',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: AppColors.primaryBlue,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AiSuggestionRow extends StatelessWidget {
  const _AiSuggestionRow({required this.text, required this.onAdd});

  final String text;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.lightBlue,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome, size: 11, color: AppColors.primaryBlue),
              SizedBox(width: 4),
              Text(
                'AI SUGGESTS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: AppColors.primaryBlue,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13.5,
              color: AppColors.darkNavy,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 8),
        InkWell(
          onTap: onAdd,
          customBorder: const CircleBorder(),
          child: Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primaryBlue,
            ),
            child: const Icon(Icons.add, size: 16, color: Colors.white),
          ),
        ),
      ],
    );
  }
}

class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, c) {
        const dashWidth = 4.0;
        const dashSpace = 3.0;
        final count = (c.maxWidth / (dashWidth + dashSpace)).floor();
        return Row(
          children: List.generate(
            count,
            (_) => Padding(
              padding: const EdgeInsets.only(right: dashSpace),
              child: Container(
                width: dashWidth,
                height: 1,
                color: AppColors.border,
              ),
            ),
          ),
        );
      },
    );
  }
}

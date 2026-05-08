import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

// Same constants used by SpeechBridge in the main isolate.
// Duplicated here because importing main-app code from the overlay isolate
// would pull in unrelated dependencies (firebase, permission_handler, etc.).
const String _mainPortName = 'speech_bridge.main';
const String _overlayPortName = 'speech_bridge.overlay';

// ── Local highlight data ─────────────────────────────────────────────────────
// Mirrors HighlightRect in ai_service.dart. Duplicated to avoid importing
// Firebase/permission_handler into the overlay isolate.
//
// (x, y, w, h) are FRACTIONS OF THE FULL SCREEN — they come from Gemini, which
// saw the entire screenshot. The painter converts them to the overlay's local
// coordinate space using `screenWidth` / `screenHeight`.
class _Highlight {
  final double x, y, w, h;
  final double screenWidth;  // logical px of the full device screen
  final double screenHeight; // logical px of the full device screen
  const _Highlight({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.screenWidth,
    required this.screenHeight,
  });
  bool get isEmpty => w == 0 && h == 0;
}

// ── Root widget ──────────────────────────────────────────────────────────────
class OverlayUI extends StatefulWidget {
  const OverlayUI({super.key});

  static const blue = Color(0xFF4A90E2);
  static const blueSoft = Color(0xFFBFD4F2);
  static const _pinkSoft = Color(0xFFF5C9C2);
  static const _greenSoft = Color(0xFFC8EBD0);
  static const _graySoft = Color(0xFFEDEEF0);
  static const _textMuted = Color(0xFF8A8F98);

  static const double _bottomGutter = 140;

  @override
  State<OverlayUI> createState() => _OverlayUIState();
}

class _OverlayUIState extends State<OverlayUI> with TickerProviderStateMixin {
  // ── IsolateNameServer port ─────────────────────────────────────────────────
  ReceivePort? _port;

  // ── Speech state ───────────────────────────────────────────────────────────
  bool _speechAvailable = true;
  bool _isListening = false;
  bool _isAnalyzing = false;
  String _lastWords = '';
  // 0..1 mic amplitude pushed from the main isolate while listening.
  double _soundLevel = 0.0;
  // True when the user explicitly tapped stop / close. The speech engine
  // emits several `status` messages while it tears down (sometimes flipping
  // listening back to true momentarily) which would otherwise trip the
  // listening->analyzing transition. We ignore the analyzing branch while
  // this flag is set, and clear it on the next start.
  bool _userCancelled = false;

  // ── Pulsing highlight animation ────────────────────────────────────────────
  late final AnimationController _highlightAnim;
  late final Animation<double> _pulseAnim;

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    // Pulsing border for the spotlight highlight
    _highlightAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _highlightAnim, curve: Curves.easeInOut),
    );

    // Register the overlay's receive port
    print('!!! OVERLAY: Registering overlay port NOW !!!');
    IsolateNameServer.removePortNameMapping(_overlayPortName);
    final port = ReceivePort();
    final ok = IsolateNameServer.registerPortWithName(
      port.sendPort,
      _overlayPortName,
    );
    print("!!! OVERLAY: Port registration result: $ok !!!");
    _port = port;
    port.listen((data) {
      if (data is Map) _onMessage(Map<String, dynamic>.from(data));
    });
  }

  @override
  void dispose() {
    _highlightAnim.dispose();
    _port?.close();
    IsolateNameServer.removePortNameMapping(_overlayPortName);
    super.dispose();
  }

  // ── Port helpers ───────────────────────────────────────────────────────────

  void _sendToMain(Map<String, dynamic> data) {
    final mainPort = IsolateNameServer.lookupPortByName(_mainPortName);
    if (mainPort == null) {
      print('!!! OVERLAY: main port not found, dropping $data !!!');
      return;
    }
    mainPort.send(data);
  }

  // ── Message handler ────────────────────────────────────────────────────────

  void _onMessage(Map<String, dynamic> data) {
    print('!!! OVERLAY RECEIVED DATA: $data !!!');
    final type = data['type'];
    if (!mounted) return;

    switch (type) {
      // ── Speech status ──────────────────────────────────────────────────────
      case 'status':
        final wasListening = _isListening;
        final nowListening = data['listening'] == true;
        setState(() {
          _speechAvailable = data['available'] == true;
          final wasListening = _isListening;
          _isListening = data['listening'] == true;
          // Only auto-flip to "Analyzing" on a real listening->stopped
          // transition that the user did NOT trigger manually. If the user
          // tapped stop / close, _userCancelled is set and we stay on Ready.
          if (wasListening && !_isListening && !_userCancelled) {
            _isAnalyzing = true;
          }
        });
        // Fallback only: if the listener stopped but no `final:true` words
        // event arrived within ~1.5s, fire with whatever we have. The primary
        // trigger lives in the 'words' case below — that's the one that
        // catches the FULL recognized phrase.
        if (wasListening && !nowListening) {
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (!mounted) return;
            if (_lastWords.trim().isNotEmpty && !_didSendAnalyze) {
              _didSendAnalyze = true;
              _sendToMain({'type': 'analyze', 'text': _lastWords.trim()});
            }
          });
        }
        break;

      // ── Interim / final speech words ───────────────────────────────────────
      case 'words':
        final text = (data['text'] as String?) ?? '';
        final isFinal = data['final'] == true;
        setState(() => _lastWords = text);
        // FINAL words = STT has fully recognized the phrase. Fire analyze NOW
        // with the complete text instead of waiting for the status change
        // (which often fires before `final:true` arrives).
        if (isFinal && text.trim().isNotEmpty && !_didSendAnalyze) {
          _didSendAnalyze = true;
          _sendToMain({'type': 'analyze', 'text': text.trim()});
        }
        break;

      // ── Mic amplitude (0.0–1.0) ───────────────────────────────────────────
      case 'level':
        setState(() {
          _soundLevel = (data['level'] as num?)?.toDouble() ?? 0.0;
        });
        break;

      // ── AI call in progress ────────────────────────────────────────────────
      case 'analyzing':
        setState(() {
          _isAnalyzing = true;
          _hidden = false; // bring overlay back if it was hidden for screenshot
          _isMinimized = false;
          _stepNumber = (data['step'] as int?) ?? _stepNumber;
          _currentInstruction = '';
          _highlight = null;
        });
        break;
      case 'level':
        final raw = (data['level'] as num?)?.toDouble() ?? 0.0;
        setState(() {
          // Light smoothing so the dot doesn't jitter frame-to-frame.
          _soundLevel = _soundLevel * 0.5 + raw.clamp(0.0, 1.0) * 0.5;
        });
        break;
    }
  }

  // ── Speech controls ────────────────────────────────────────────────────────

  void _startListening() {
    print("OVERLAY: Sending 'start' command to Main App...");
    _sendToMain({'type': 'start'});
    setState(() {
      _isListening = true;
      _isAnalyzing = false;
      _lastWords = '';
      _soundLevel = 0.0;
      _userCancelled = false;
    });
  }

  void _stopListening() {
    // Manual stop = user cancelled. Go back to Ready, NOT Analyzing.
    // _userCancelled tells _onMessage to ignore the listening->stopped
    // status echoes the speech engine emits during teardown.
    setState(() {
      _isListening = false;
      _isAnalyzing = false;
      _soundLevel = 0.0;
      _userCancelled = true;
    });
    _sendToMain({'type': 'stop'});
  }

  void _resetToReady() {
    setState(() {
      _isAnalyzing = false;
      _isListening = false;
      _lastWords = '';
      _soundLevel = 0.0;
      _userCancelled = true;
    });
  }

  // ── Window size helpers ────────────────────────────────────────────────────

  // Solo encogemos / agrandamos el overlay existente. Sin close/reopen.
  Future<void> _minimize() async {
    setState(() => _isMinimized = true);
    await FlutterOverlayWindow.resizeOverlay(140, 320, true);
  }

  Future<void> _expand() async {
    await FlutterOverlayWindow.resizeOverlay(1150, WindowSize.matchParent, true);
    setState(() => _isMinimized = false);
  }

  // ── AI guidance actions ────────────────────────────────────────────────────

  void _onNextStep() {
    setState(() {
      _currentInstruction = '';
      _highlight = null;
      _isAnalyzing = true;
    });
    _sendToMain({'type': 'next_step'});
  }

  void _onNewQuestion() {
    setState(() {
      _currentInstruction = '';
      _highlight = null;
      _isComplete = false;
      _lastWords = '';
      _isAnalyzing = false;
      _didSendAnalyze = false;
    });
    _startListening();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // ── Spotlight overlay ──────────────────────────────────────────────
          if (showHighlight)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _pulseAnim,
                builder: (context, _) => CustomPaint(
                  painter: _HighlightPainter(
                    highlight: _highlight!,
                    pulse: _pulseAnim.value,
                  ),
                ),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: _isAnalyzing
                    ? _buildAnalyzingCard()
                    : _buildListeningCard(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListeningCard() {
    final title = _isListening ? 'Listening...' : 'Ready';
    final hasTranscript = _lastWords.isNotEmpty;
    final placeholder = !_speechAvailable
        ? 'Speech unavailable'
        : _isListening
        ? 'Tell me what you need help with'
        : 'Tap the mic to start';

    return Column(
      key: const ValueKey('listening-card'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _ListeningIndicator(active: _isListening, level: _soundLevel),
        const SizedBox(height: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: hasTranscript
                  ? Padding(
                      key: const ValueKey('transcript'),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        '“${_lastWords.trim()}”',
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          height: 1.3,
                          color: Color(0xFF1F2937),
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    )
                  : Text(
                      placeholder,
                      key: ValueKey('placeholder:$placeholder'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        color: OverlayUI._textMuted,
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _CircleButton(
              color: OverlayUI._graySoft,
              iconColor: const Color(0xFF6B7280),
              icon: Icons.remove,
              onTap: () => FlutterOverlayWindow.shareData({'type': 'minimize'}),
            ),
            const SizedBox(width: 14),
            _CircleButton(
              color: _isListening ? OverlayUI._pinkSoft : OverlayUI._greenSoft,
              iconColor: OverlayUI.blue,
              icon: _isListening ? Icons.stop : Icons.mic,
              onTap: _isListening ? _stopListening : _startListening,
            ),
            const SizedBox(width: 14),
            _CircleButton(
              color: OverlayUI._pinkSoft,
              iconColor: const Color(0xFFC2453A),
              icon: Icons.close,
              onTap: () async {
                setState(() {
                  _isListening = false;
                  _isAnalyzing = false;
                  _lastWords = '';
                  _userCancelled = true;
                });
                _sendToMain({'type': 'stop'});
                await FlutterOverlayWindow.closeOverlay();
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAnalyzingCard() {
    return Padding(
      key: const ValueKey('analyzing-card'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const _AnalyzingDots(),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text(
                  'Looking at your screen',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Analyzing what you need help with',
                  style: TextStyle(fontSize: 13, color: OverlayUI._textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _CircleButton(
            color: OverlayUI._graySoft,
            iconColor: const Color(0xFF6B7280),
            icon: Icons.arrow_back,
            onTap: _resetToReady,
          ),
        ],
      ),
      child: child,
    );
  }
}

// ── Highlight painter ──────────────────────────────────────────────────────

/// Dark semi-transparent overlay with a transparent cutout revealing the
/// element the user must tap, plus a pulsing blue border and corner accents.
class _HighlightPainter extends CustomPainter {
  final _Highlight highlight;
  final double pulse; // 0.0 → 1.0

  const _HighlightPainter({required this.highlight, required this.pulse});

  @override
  void paint(Canvas canvas, Size size) {
    const padding = 8.0;

    // ── Coordinate conversion ──
    // Gemini's fractions are relative to the FULL SCREEN. The overlay only
    // covers the bottom `size.height` logical pixels of a `screenHeight`-tall
    // screen, so we need to translate Y from screen-space to overlay-space.
    //
    //   screen y in pixels = highlight.y * screenHeight
    //   overlay top on screen = screenHeight - size.height
    //   overlay-local y in pixels = screen_y - overlay_top
    final overlayTopOnScreen = highlight.screenHeight - size.height;

    final screenX = highlight.x * highlight.screenWidth;
    final screenY = highlight.y * highlight.screenHeight;
    final screenW = highlight.w * highlight.screenWidth;
    final screenH = highlight.h * highlight.screenHeight;

    // The overlay is full-width, so x maps 1-to-1 once we account for any
    // potential horizontal offset (currently zero — overlay is matchParent).
    final rx = screenX;
    final ry = screenY - overlayTopOnScreen;
    final rw = screenW;
    final rh = screenH;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
          rx - padding, ry - padding, rw + padding * 2, rh + padding * 2),
      const Radius.circular(12),
    );

    // Semi-transparent dark film with a cut-out
    final filmPaint = Paint()..color = Colors.black.withOpacity(0.45);
    final fullRect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawPath(
      Path()
        ..addRect(fullRect)
        ..addRRect(rrect)
        ..fillType = PathFillType.evenOdd,
      filmPaint,
    );

    // Pulsing border
    final borderPaint = Paint()
      ..color = OverlayUI.blue.withOpacity(0.6 + 0.4 * pulse)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5 + 1.5 * pulse;
    canvas.drawRRect(rrect, borderPaint);

    // White corner accents
    _drawCorners(canvas, rrect.outerRect, pulse);
  }

  void _drawCorners(Canvas canvas, Rect r, double pulse) {
    const len = 16.0;
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..strokeWidth = 3.0 + pulse
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final corners = <List<Offset>>[
      // Top-left
      [Offset(r.left, r.top + len), Offset(r.left, r.top), Offset(r.left + len, r.top)],
      // Top-right
      [Offset(r.right - len, r.top), Offset(r.right, r.top), Offset(r.right, r.top + len)],
      // Bottom-left
      [Offset(r.left, r.bottom - len), Offset(r.left, r.bottom), Offset(r.left + len, r.bottom)],
      // Bottom-right
      [Offset(r.right - len, r.bottom), Offset(r.right, r.bottom), Offset(r.right, r.bottom - len)],
    ];

    for (final c in corners) {
      canvas.drawPath(
        Path()
          ..moveTo(c[0].dx, c[0].dy)
          ..lineTo(c[1].dx, c[1].dy)
          ..lineTo(c[2].dx, c[2].dy),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_HighlightPainter old) =>
      old.pulse != pulse || old.highlight != highlight;
}

// ── Listening indicator ────────────────────────────────────────────────────

/// Sonar-style pulse that also reacts to the real microphone amplitude
/// (passed via [level]). Pulse only runs when [active] is true.
class _ListeningIndicator extends StatefulWidget {
  const _ListeningIndicator({required this.active, this.level = 0.0});

  final bool active;
  // 0..1 mic amplitude. Drives an extra "voice bump" on top of the
  // baseline breathe animation while the user is speaking.
  final double level;

  @override
  State<_ListeningIndicator> createState() => _ListeningIndicatorState();
}

class _ListeningIndicatorState extends State<_ListeningIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (widget.active) _controller.repeat();
  }

  @override
  void didUpdateWidget(_ListeningIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const baseSize = 52.0;
    const maxRipple = 84.0;
    final levelBoost = widget.level * 14.0;

    return SizedBox(
      width: maxRipple + levelBoost,
      height: maxRipple + levelBoost,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = Curves.easeOut.transform(_controller.value);
          // Mic-driven boost: ripple grows bigger and stays brighter when
          // the user is louder. level is already smoothed in the parent.
          final lvl = widget.active ? widget.level.clamp(0.0, 1.0) : 0.0;
          final rippleSize =
              baseSize + (maxRipple - baseSize) * t * (0.4 + 0.6 * lvl);
          final rippleOpacity =
              widget.active ? (1 - t) * (0.25 + 0.6 * lvl) : 0.0;
          // Baseline breathe + extra punch from the user's voice.
          final breathe = widget.active
              ? 1.0 +
                  0.08 * (1 - (2 * _controller.value - 1).abs()) +
                  0.35 * lvl
              : 1.0;
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: rippleSize,
                height: rippleSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: OverlayUI.blueSoft.withOpacity(rippleOpacity),
                ),
              ),
              Container(
                width: baseSize,
                height: baseSize,
                decoration: const BoxDecoration(
                  color: OverlayUI.blueSoft,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Transform.scale(
                  scale: breathe,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: const BoxDecoration(
                      color: OverlayUI.blue,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Three blue dots that pulse in a wave — used while the assistant is
/// "analyzing the screen". Pure visual: no work is actually being done here,
/// the screenshot/agent wiring lives elsewhere.
class _AnalyzingDots extends StatefulWidget {
  const _AnalyzingDots();

  @override
  State<_AnalyzingDots> createState() => _AnalyzingDotsState();
}

class _AnalyzingDotsState extends State<_AnalyzingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                // Stagger each dot by 1/3 of the loop.
                final phase = (_controller.value - i * 0.18) % 1.0;
                final wave = (phase < 0.5)
                    ? phase * 2
                    : (1 - phase) * 2; // 0 -> 1 -> 0
                final eased = Curves.easeInOut.transform(wave.clamp(0.0, 1.0));
                final scale = 0.7 + 0.5 * eased;
                final opacity = 0.35 + 0.65 * eased;
                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: i == 1 ? 3 : 2),
                  child: Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: OverlayUI.blue.withOpacity(opacity),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.color,
    required this.iconColor,
    required this.icon,
    required this.onTap,
  });

  final Color color;
  final Color iconColor;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 28,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Icon(icon, size: 20, color: iconColor),
      ),
    );
  }
}

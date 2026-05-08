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
  String _lastWords = '';
  bool _didSendAnalyze = false;
  double _soundLevel = 0.0;

  // ── AI guidance state ──────────────────────────────────────────────────────
  bool _isAnalyzing = false;
  String _currentInstruction = '';
  _Highlight? _highlight;
  bool _isComplete = false;
  int _stepNumber = 1;

  // ── UI state ───────────────────────────────────────────────────────────────
  bool _isMinimized = false;
  // Renders the overlay completely invisible while the main app captures a
  // clean screenshot. Toggled via 'hide' / 'analyzing' messages.
  bool _hidden = false;

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
    final ok =
        IsolateNameServer.registerPortWithName(port.sendPort, _overlayPortName);
    print('!!! OVERLAY: Port registration result: $ok !!!');
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
          _isListening = nowListening;
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

      // ── Temporarily hide the overlay so the screenshot captures the
      //    user's app cleanly (no AI assistant card on top). The next
      //    'analyzing' / 'ai_step' / 'ai_error' message will un-hide it.
      case 'hide':
        setState(() => _hidden = true);
        break;

      // ── AI returned a guidance step ────────────────────────────────────────
      case 'ai_step':
        final h = data['highlight'];
        final screenW = (data['screen_width'] as num?)?.toDouble() ?? 0;
        final screenH = (data['screen_height'] as num?)?.toDouble() ?? 0;
        setState(() {
          _hidden = false; // overlay must be visible to show the result
          _isAnalyzing = false;
          _currentInstruction = (data['instruction'] as String?) ?? '';
          _stepNumber = (data['step_number'] as int?) ?? 1;
          _isComplete = data['is_complete'] == true;
          _highlight = (h is Map && screenW > 0 && screenH > 0)
              ? _Highlight(
                  x: (h['x'] as num).toDouble(),
                  y: (h['y'] as num).toDouble(),
                  w: (h['w'] as num).toDouble(),
                  h: (h['h'] as num).toDouble(),
                  screenWidth: screenW,
                  screenHeight: screenH,
                )
              : null;
          _isMinimized = false;
        });
        break;

      // ── AI error ───────────────────────────────────────────────────────────
      case 'ai_error':
        setState(() {
          _hidden = false; // ensure overlay is visible to show the error
          _isAnalyzing = false;
          _currentInstruction =
              (data['message'] as String?) ?? 'Something went wrong. Please try again.';
          _highlight = null;
          _isComplete = false;
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
      _didSendAnalyze = false;
      _lastWords = '';
      _currentInstruction = '';
      _highlight = null;
      _isComplete = false;
    });
  }

  void _stopListening() {
    // Don't send `analyze` here — the `status` handler does it the moment the
    // listener actually transitions to not-listening. That handles BOTH manual
    // stop AND auto-stop on silence consistently.
    _sendToMain({'type': 'stop'});
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
    // While hidden (during screenshot capture), draw nothing — the underlying
    // app should be visible and the screenshot should be clean.
    if (_hidden) {
      return const Material(color: Colors.transparent);
    }

    final showHighlight =
        _highlight != null && !_highlight!.isEmpty && !_isMinimized;

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
            ),

          // ── Card / pill ────────────────────────────────────────────────────
          if (_isMinimized)
            _buildMinimizedPill()
          else if (_isAnalyzing)
            _buildAnalyzingCard()
          else if (_currentInstruction.isNotEmpty)
            _buildResultCard()
          else
            _buildListeningCard(),
        ],
      ),
    );
  }

  // ── Minimized pill ─────────────────────────────────────────────────────────

  Widget _buildMinimizedPill() {
    // Padding superior para no quedar tapado por el status bar de Android.
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 36, 10, 10),
      child: GestureDetector(
        onTap: _expand,
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            color: OverlayUI.blue,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.30),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.assistant, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text(
                'HelpVrywhere',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Listening card ─────────────────────────────────────────────────────────

  Widget _buildListeningCard() {
    final hasTranscript = _lastWords.isNotEmpty;
    final title = _isListening ? 'Listening...' : 'Ready';
    final placeholder = !_speechAvailable
        ? 'Speech unavailable'
        : _isListening
            ? 'Tell me what you need help with'
            : 'Tap the mic to start';

    return Positioned(
      left: 12,
      right: 12,
      bottom: OverlayUI._bottomGutter,
      child: _card(
        child: Column(
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
                          padding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            '"${_lastWords.trim()}"',
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
                  onTap: _minimize,
                ),
                const SizedBox(width: 14),
                _CircleButton(
                  color: _isListening
                      ? OverlayUI._pinkSoft
                      : OverlayUI._greenSoft,
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
                    _sendToMain({'type': 'stop'});
                    await FlutterOverlayWindow.closeOverlay();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Analyzing card ─────────────────────────────────────────────────────────

  Widget _buildAnalyzingCard() {
    return Positioned(
      left: 12,
      right: 12,
      bottom: OverlayUI._bottomGutter,
      child: _card(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor:
                    AlwaysStoppedAnimation<Color>(OverlayUI.blue),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Analyzing screen...',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Step $_stepNumber — Looking at what\'s on screen',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: OverlayUI._textMuted,
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ── Result card ────────────────────────────────────────────────────────────

  Widget _buildResultCard() {
    return Positioned(
      left: 12,
      right: 12,
      bottom: OverlayUI._bottomGutter,
      child: _card(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: step badge + minimize + close
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: OverlayUI.blueSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _isComplete ? '✓ Done' : 'Step $_stepNumber',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: OverlayUI.blue,
                    ),
                  ),
                ),
                const Spacer(),
                _CircleButton(
                  color: OverlayUI._graySoft,
                  iconColor: const Color(0xFF6B7280),
                  icon: Icons.remove,
                  onTap: _minimize,
                ),
                const SizedBox(width: 8),
                _CircleButton(
                  color: OverlayUI._pinkSoft,
                  iconColor: const Color(0xFFC2453A),
                  icon: Icons.close,
                  onTap: () async {
                    _sendToMain({'type': 'stop'});
                    await FlutterOverlayWindow.closeOverlay();
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Instruction text
            Text(
              _currentInstruction,
              style: const TextStyle(
                fontSize: 16,
                height: 1.4,
                color: Color(0xFF1F2937),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),

            // Action buttons
            if (_isComplete) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    _sendToMain({'type': 'stop'});
                    await FlutterOverlayWindow.closeOverlay();
                  },
                  icon:
                      const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Close Assistant'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: OverlayUI._greenSoft,
                    foregroundColor: const Color(0xFF22863A),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding:
                        const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _onNextStep,
                      icon: const Icon(Icons.arrow_forward, size: 16),
                      label: const Text('I did it → Next'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: OverlayUI.blue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _CircleButton(
                    color: OverlayUI._graySoft,
                    iconColor: const Color(0xFF6B7280),
                    icon: Icons.mic,
                    onTap: _onNewQuestion,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Card container helper ──────────────────────────────────────────────────

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEAECEF)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 6),
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
  final double level; // 0.0–1.0, drives the extra ripple boost

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
          final rippleSize =
              baseSize + (maxRipple - baseSize) * t + levelBoost;
          final rippleOpacity = widget.active ? (1 - t) * 0.55 : 0.0;
          final breathe = widget.active
              ? 1.0 + 0.08 * (1 - (2 * _controller.value - 1).abs())
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

// ── Circle button ──────────────────────────────────────────────────────────

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

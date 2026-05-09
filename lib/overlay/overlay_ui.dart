import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

// Same constants used by SpeechBridge in the main isolate.
// Duplicated here because importing main-app code from the overlay isolate
// would pull in unrelated dependencies (firebase, permission_handler, etc.).
const String _mainPortName = 'speech_bridge.main';
const String _overlayPortName = 'speech_bridge.overlay';

// (Region / glow code removed — voice-first design now uses a movable
// instruction pill instead of a spatial highlight on the screen.)

// ── Root widget ──────────────────────────────────────────────────────────────
class OverlayUI extends StatefulWidget {
  const OverlayUI({super.key});

  static const blue = Color(0xFF4A90E2);
  static const blueSoft = Color(0xFFBFD4F2);
  static const _pinkSoft = Color(0xFFF5C9C2);
  static const _greenSoft = Color(0xFFC8EBD0);
  static const _graySoft = Color(0xFFEDEEF0);
  static const _textMuted = Color(0xFF8A8F98);

  // Distance from the BOTTOM of the overlay window to the bottom edge of
  // the card. The Android gesture nav bar can be 60–80 dp tall on
  // Pixel-class devices, so the gutter must clear that AND leave a few
  // visible dp between the lowest button and the gesture bar.
  static const double _bottomGutter = 130;

  @override
  State<OverlayUI> createState() => _OverlayUIState();
}

class _OverlayUIState extends State<OverlayUI> {
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
  bool _isComplete = false;
  int _stepNumber = 1;

  // ── UI state ───────────────────────────────────────────────────────────────
  bool _isMinimized = false;
  // Renders the overlay completely invisible while the main app captures a
  // clean screenshot. Toggled via 'hide' / 'analyzing' messages.
  bool _hidden = false;

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    // Register the overlay's receive port
    print('!!! OVERLAY: Registering overlay port NOW !!!');
    IsolateNameServer.removePortNameMapping(_overlayPortName);
    final port = ReceivePort();
    final ok = IsolateNameServer.registerPortWithName(
      port.sendPort,
      _overlayPortName,
    );
    print('!!! OVERLAY: Port registration result: $ok !!!');
    _port = port;
    port.listen((data) {
      if (data is Map) _onMessage(Map<String, dynamic>.from(data));
    });
  }

  @override
  void dispose() {
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
        final wasMinimized = _isMinimized;
        setState(() {
          _isAnalyzing = true;
          _hidden = false; // bring overlay back if it was hidden for screenshot
          _stepNumber = (data['step'] as int?) ?? _stepNumber;
          _currentInstruction = '';
        });
        // CRITICAL: if we were in the small pill window when this arrived,
        // we MUST resize the native window back to full overlay size or
        // the analyzing card will paint into the 220-px pill and get
        // clipped. _expand handles both the resize AND clearing the
        // _isMinimized flag.
        if (wasMinimized) {
          _expand();
        } else {
          setState(() => _isMinimized = false);
        }
        break;

      // ── Temporarily hide the overlay so the screenshot captures the
      //    user's app cleanly (no AI assistant card on top). The next
      //    'analyzing' / 'ai_step' / 'ai_error' message will un-hide it.
      case 'hide':
        setState(() => _hidden = true);
        break;

      // ── AI returned a guidance step ────────────────────────────────────────
      case 'ai_step':
        setState(() {
          _hidden = false;
          _isAnalyzing = false;
          _currentInstruction = (data['instruction'] as String?) ?? '';
          _stepNumber = (data['step_number'] as int?) ?? 1;
          _isComplete = data['is_complete'] == true;
        });
        // Voice-first flow:
        //   - In-progress step  → collapse to the pill so the user can tap
        //                         the element described in the instruction.
        //   - Goal complete     → make sure we're EXPANDED so the full
        //                         success card (with "Close Assistant"
        //                         button) is visible. If we don't resize
        //                         here, the success card paints into the
        //                         220-px pill window and gets clipped.
        if (_isComplete) {
          if (_isMinimized) _expand();
        } else {
          _minimize();
        }
        break;

      // ── AI error ───────────────────────────────────────────────────────────
      case 'ai_error':
        setState(() {
          _hidden = false;
          _isAnalyzing = false;
          _currentInstruction =
              (data['message'] as String?) ??
              'Something went wrong. Please try again.';
          _isComplete = false;
        });
        // Same fix: if the error arrived while we were in pill mode, grow
        // back to the full overlay so the error card has room.
        if (_isMinimized) _expand();
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

  // Resize the existing overlay window without close/reopen.
  //
  // CAREFUL #1: `resizeOverlay`'s signature is `(width, height, enableDrag)`,
  // NOT `(height, width, ...)`. Passing them in the wrong order produces a
  // 140-px-wide window that squishes the pill.
  //
  // CAREFUL #2: After `resizeOverlay()` Android resizes the native window
  // but flutter_overlay_window 0.4.x does NOT always push the new
  // BoxConstraints into the Flutter widget tree right away. If we just
  // setState once, the pill is laid out against the *previous* (1150-tall)
  // constraints and ends up rendered above the visible 140px strip — the
  // user sees nothing until a second event (anything) triggers a rebuild,
  // which is exactly the "first time minimize disappears, second time it
  // works" symptom. The second `setState({})` after a short delay forces
  // Flutter to re-lay out against the new window size.
  Future<void> _minimize() async {
    setState(() => _isMinimized = true);
    // Larger pill than before — needs to fit two lines of instruction text
    // + a "Did it" button on the instruction pill, while still being small
    // enough to drag freely around the screen.
    await FlutterOverlayWindow.resizeOverlay(
      WindowSize.matchParent, // width  — full width feels less awkward
      //                                  than a centered floating bar
      220, // height
      true, // enableDrag — pill is movable
    );
    if (!mounted) return;
    await Future.delayed(const Duration(milliseconds: 80));
    if (mounted) setState(() {}); // force re-layout against the new window
  }

  Future<void> _expand() async {
    // MUST match the height in showOverlay (need_help.dart). 1100 px
    // ≈ 367 dp on a 3× phone — fits the listening card AND clears the
    // gesture nav bar (which on some devices is 60–80 dp tall).
    await FlutterOverlayWindow.resizeOverlay(
      WindowSize.matchParent,
      1100,
      false, // enableDrag = false — only the minimized pill is movable
    );
    // Reset the window's drag offset. Android keeps the dragged offset on
    // the window even after a resizeOverlay, so without this the
    // expanded overlay would be shifted by however far the user dragged
    // the pill — that's why the success card was getting half-clipped.
    await FlutterOverlayWindow.moveOverlay(OverlayPosition(0, 0));
    if (!mounted) return;
    setState(() => _isMinimized = false);
    await Future.delayed(const Duration(milliseconds: 80));
    if (mounted) setState(() {}); // forced re-layout against the new window
  }

  /// Reset the pill's drag offset back to the default position. Bound to
  /// the recenter button on the instruction pill so the user can recover
  /// when they've dragged the bubble somewhere awkward.
  Future<void> _recenterPill() async {
    await FlutterOverlayWindow.moveOverlay(OverlayPosition(0, 0));
  }

  /// Tear down everything before closing the overlay. Called by the X
  /// button and by the "Close Assistant" success button so state is fully
  /// reset for the NEXT session — the bridge stops TTS / STT and clears
  /// `_currentGoal` / `_currentStep`, and we clear the overlay's local
  /// state too in case the widget is reused before disposal.
  Future<void> _closeAndReset() async {
    _sendToMain({'type': 'close'});
    if (mounted) {
      setState(() {
        _isListening = false;
        _isAnalyzing = false;
        _isMinimized = false;
        _isComplete = false;
        _currentInstruction = '';
        _lastWords = '';
        _stepNumber = 1;
        _didSendAnalyze = false;
        _hidden = false;
        _soundLevel = 0.0;
      });
    }
    await FlutterOverlayWindow.closeOverlay();
  }

  // ── AI guidance actions ────────────────────────────────────────────────────

  void _onNextStep() {
    setState(() {
      _currentInstruction = '';
      _isAnalyzing = true;
    });
    _sendToMain({'type': 'next_step'});
  }

  void _onNewQuestion() {
    setState(() {
      _currentInstruction = '';
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

    // EARLY RETURN for the minimized state.
    //
    // Plain Container(alignment: center) instead of Stack/Positioned so the
    // pill renders correctly even on the first minimize, before
    // flutter_overlay_window has propagated the new window constraints to
    // the Flutter side.
    if (_isMinimized) {
      return Material(
        color: Colors.transparent,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.all(8),
          child: _currentInstruction.isNotEmpty
              ? _instructionPill()
              : _idlePill(),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          if (_isAnalyzing)
            _buildAnalyzingCard()
          else if (_currentInstruction.isNotEmpty)
            _buildResultCard()
          else
            _buildListeningCard(),
        ],
      ),
    );
  }

  // ── Idle pill ──────────────────────────────────────────────────────────────
  // Shown when the overlay has been minimized but there is no AI
  // instruction to display yet (e.g. user manually minimized while
  // listening). Tapping it expands the overlay back to the full UI.
  Widget _idlePill() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: _expand,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: OverlayUI.blue,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.30),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
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
        const SizedBox(width: 8),
        // Small recenter button next to the idle pill so users can
        // bring it back if they dragged it off-screen.
        Material(
          color: Colors.white,
          shape: const CircleBorder(),
          elevation: 2,
          child: InkResponse(
            onTap: _recenterPill,
            radius: 22,
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(
                Icons.center_focus_strong,
                size: 18,
                color: OverlayUI.blue,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Instruction pill ───────────────────────────────────────────────────────
  // The hero of the voice-first design. After Gemini returns an
  // instruction the overlay auto-collapses to this banner-sized pill that
  // stays draggable, lets the user tap through to the underlying app, and
  // keeps the next step visible while their finger is hunting.
  //
  // Layout:
  //   ┌──────────────────────────────────────────────┐
  //   │  Step 1                                      │
  //   │  Tap the red square with a white play …      │
  //   │                              [✓ I did it]    │
  //   └──────────────────────────────────────────────┘
  //
  // - Tap text → expand to the full result card (replay voice, see all
  //   options).
  // - Tap "I did it" → advance to the next step without expanding.
  Widget _instructionPill() {
    return GestureDetector(
      onTap: _expand, // tap-anywhere-but-the-button → expand
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFEAECEF)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Step badge + recenter button + drag-handle hint.
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: OverlayUI.blueSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _isComplete ? '✓ Done' : 'Step $_stepNumber',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: OverlayUI.blue,
                    ),
                  ),
                ),
                const Spacer(),
                // Recenter — moves the dragged pill back to its default
                // alignment-anchored position. We use a Tooltip so an
                // elderly user who long-presses gets a hint.
                Tooltip(
                  message: 'Move bubble back',
                  child: InkResponse(
                    radius: 22,
                    onTap: _recenterPill,
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(
                        Icons.center_focus_strong,
                        size: 18,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.drag_indicator,
                  size: 18,
                  color: Color(0xFFB0B5BC),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Instruction text — 2 lines max so the pill stays compact;
            // user taps to expand for the full version.
            Text(
              _currentInstruction,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                height: 1.35,
                color: Color(0xFF1F2937),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _onNextStep,
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text(
                    'I did it',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: OverlayUI.blue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Minimized pill ─────────────────────────────────────────────────────────

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
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 4),
            // Fixed-height slot for the transcript / placeholder. Locked
            // min == max so the card height never changes as the user
            // speaks longer phrases.
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48, maxHeight: 48),
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: hasTranscript
                      ? Padding(
                          key: const ValueKey('transcript'),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            '"${_lastWords.trim()}"',
                            textAlign: TextAlign.center,
                            maxLines: 2,
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
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _CircleButton(
                  color: OverlayUI._graySoft,
                  iconColor: const Color(0xFF6B7280),
                  icon: Icons.remove,
                  onTap: _minimize,
                ),
                const SizedBox(width: 12),
                _CircleButton(
                  color: _isListening
                      ? OverlayUI._pinkSoft
                      : OverlayUI._greenSoft,
                  iconColor: OverlayUI.blue,
                  icon: _isListening ? Icons.stop : Icons.mic,
                  onTap: _isListening ? _stopListening : _startListening,
                ),
                const SizedBox(width: 12),
                _CircleButton(
                  color: OverlayUI._pinkSoft,
                  iconColor: const Color(0xFFC2453A),
                  icon: Icons.close,
                  onTap: _closeAndReset,
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
                valueColor: AlwaysStoppedAnimation<Color>(OverlayUI.blue),
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
              style: const TextStyle(fontSize: 13, color: OverlayUI._textMuted),
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
                    horizontal: 10,
                    vertical: 4,
                  ),
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
                  onTap: _closeAndReset,
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
                  onPressed: _closeAndReset,
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Close Assistant'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: OverlayUI._greenSoft,
                    foregroundColor: const Color(0xFF22863A),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
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
                        padding: const EdgeInsets.symmetric(vertical: 12),
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
      // Tightened from 20/18 to 18/14 to claw back vertical space inside
      // the now-shorter 850-px overlay.
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
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

// (Region glow painter removed — voice-first design uses the instruction
// pill instead of a screen highlight.)

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
    // Compact sizes tuned to fit the listening card inside the 850-px
    // overlay (≈283 dp on a 3× density screen). The ripple still pulses
    // visibly with the user's voice but the indicator no longer
    // dominates the card vertically.
    const baseSize = 36.0;
    const maxRipple = 56.0;
    // Maximum extra growth the ripple may add when the user speaks loudly.
    const maxLevelBoost = 8.0;
    // Outer slot size is FIXED — never depends on `level`. If we let the
    // SizedBox grow with the mic amplitude, the listening card (which is
    // anchored to a fixed `bottom`) would shift upward every time the
    // user spoke louder, making the overlay appear to move.
    const slotSize = maxRipple + maxLevelBoost;
    // The growth still happens, but only inside this fixed-size slot — using
    // ClipOval to keep things visually clean if the ripple ever exceeds it.
    final levelBoost = widget.level.clamp(0.0, 1.0) * maxLevelBoost;

    return SizedBox(
      width: slotSize,
      height: slotSize,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = Curves.easeOut.transform(_controller.value);
          final rippleSize = baseSize + (maxRipple - baseSize) * t + levelBoost;
          final rippleOpacity = widget.active ? (1 - t) * 0.55 : 0.0;
          // Inner dark-blue dot now reacts to the mic amplitude on top of
          // its baseline auto-pulse. The two terms add together:
          //   - 0.08 * pulse  → gentle "I'm alive" breathe at silence.
          //   - 0.40 * lvl    → loud-voice punch (up to ~+40% scale).
          // The dot stays centered inside the ring so the layout doesn't
          // shift as it grows.
          final lvl = widget.active ? widget.level.clamp(0.0, 1.0) : 0.0;
          final breathe = widget.active
              ? 1.0 +
                  0.08 * (1 - (2 * _controller.value - 1).abs()) +
                  0.40 * lvl
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
                    width: 16,
                    height: 16,
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

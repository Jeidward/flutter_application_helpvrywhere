import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

// Same constants used by SpeechBridge in the main isolate.
// Duplicated here because importing main-app code from the overlay isolate
// would pull in unrelated dependencies (firebase, permission_handler, etc.).
const String _mainPortName = 'speech_bridge.main';
const String _overlayPortName = 'speech_bridge.overlay';

/// Change this file to change the overlay
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

class _OverlayUIState extends State<OverlayUI> {
  // The overlay can't run speech_to_text itself (no Activity context).
  // The flutter_overlay_window 0.4.5 channel only works main→overlay
  // (overlay→main is silently dropped), so we use IsolateNameServer
  // ports for both directions instead.
  ReceivePort? _port;

  bool _speechAvailable = true;
  bool _isListening = false;
  bool _isAnalyzing = false;
  String _lastWords = '';
  // 0..1 mic amplitude pushed from the main isolate while listening.
  double _soundLevel = 0.0;

  @override
  void initState() {
    super.initState();
    print("!!! OVERLAY: Registering overlay port NOW !!!");
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
    _port?.close();
    IsolateNameServer.removePortNameMapping(_overlayPortName);
    super.dispose();
  }

  void _sendToMain(Map<String, dynamic> data) {
    final mainPort = IsolateNameServer.lookupPortByName(_mainPortName);
    if (mainPort == null) {
      print("!!! OVERLAY: main port not found, dropping $data !!!");
      return;
    }
    mainPort.send(data);
  }

  void _onMessage(Map<String, dynamic> data) {
    print("!!! OVERLAY RECEIVED DATA: $data !!!");
    final type = data['type'];
    if (!mounted) return;
    switch (type) {
      case 'status':
        setState(() {
          _speechAvailable = data['available'] == true;
          final wasListening = _isListening;
          _isListening = data['listening'] == true;
          // If listening transitioned true -> false (user stopped speaking
          // or engine timed out), move into the analyzing state.
          // The close button locally clears _isListening *before* sending
          // stop, so by the time its echo arrives wasListening is already
          // false and this branch correctly does NOT fire.
          if (wasListening && !_isListening) {
            _isAnalyzing = true;
          }
        });
        break;
      case 'words':
        setState(() {
          _lastWords = (data['text'] as String?) ?? '';
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

  void _startListening() {
    print("OVERLAY: Sending 'start' command to Main App...");
    _sendToMain({'type': 'start'});
    setState(() {
      _isListening = true;
      _isAnalyzing = false;
      _lastWords = '';
      _soundLevel = 0.0;
    });
  }

  void _stopListening() {
    // Manual stop = user cancelled. Go back to Ready, NOT Analyzing.
    // We clear _isListening locally first so when the main isolate echoes
    // back its `status` (listening:false) message, the wasListening->!isListening
    // branch in _onMessage sees wasListening already false and does not
    // flip us into the analyzing state.
    setState(() {
      _isListening = false;
      _isAnalyzing = false;
      _soundLevel = 0.0;
    });
    _sendToMain({'type': 'stop'});
  }

  void _resetToReady() {
    setState(() {
      _isAnalyzing = false;
      _isListening = false;
      _lastWords = '';
      _soundLevel = 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned(
            left: 12,
            right: 12,
            bottom: OverlayUI._bottomGutter,
            child: Container(
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
    );
  }
}

/// Sonar-style pulse: a static blue dot inside a soft ring, with a second
/// ring that expands outward and fades — gives a "live, listening" feel.
/// Pulse only runs when [active] is true; otherwise it sits still.
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
    return SizedBox(
      width: maxRipple,
      height: maxRipple,
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

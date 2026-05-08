import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'ai_service.dart';

/// Owns the SpeechToText plugin, the TTS engine, and the AI service — all
/// in the MAIN app isolate, where an Activity context exists.
///
/// The overlay (separate Flutter engine inside a Service) cannot use any of
/// these plugins directly, so we bridge via IsolateNameServer ports.
///
/// ── Wire protocol ────────────────────────────────────────────────────────
///
/// Overlay → Main:
///   {'type': 'start'}
///   {'type': 'stop'}
///   {'type': 'analyze', 'text': String}   ← speech result is final, run AI
///   {'type': 'next_step'}                 ← screen changed, advance step
///
/// Main → Overlay:
///   {'type': 'status',   'listening': bool, 'available': bool}
///   {'type': 'words',    'text': String, 'final': bool}
///   {'type': 'level',    'level': double}         ← mic amplitude 0‥1
///   {'type': 'analyzing','step': int}             ← AI call in progress
///   {'type': 'ai_step',  'instruction': String,   ← AI response
///                        'step_number': int,
///                        'is_complete': bool,
///                        'highlight': {'x','y','w','h'} | absent}
///   {'type': 'ai_error', 'message': String}
/// ─────────────────────────────────────────────────────────────────────────
class SpeechBridge {
  SpeechBridge._();
  static final SpeechBridge instance = SpeechBridge._();

  // ── Port names ─────────────────────────────────────────────────────────
  static const String mainPortName = 'speech_bridge.main';
  static const String overlayPortName = 'speech_bridge.overlay';

  // ── Native channel for screenshots (implemented in MainActivity.kt) ────
  static const _screenshotChannel = MethodChannel('app/screenshot');

  // ── Plugin instances ───────────────────────────────────────────────────
  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final AiService _aiService = AiService();

  ReceivePort? _port;
  bool _initialized = false;

  // ── Guidance session state ─────────────────────────────────────────────
  String _currentGoal = '';
  int _currentStep = 1;
  bool _isAnalyzing = false;


  // ─────────────────────────────────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────────────────────────────────

  /// Call once at app startup (main.dart) to open the receive port and
  /// initialize TTS.
  void registerOverlayListener() {
    if (_port != null) return;
    print('!!! MAIN APP: Registering IsolateNameServer port NOW !!!');
    IsolateNameServer.removePortNameMapping(mainPortName);
    final port = ReceivePort();
    final ok =
        IsolateNameServer.registerPortWithName(port.sendPort, mainPortName);
    print('!!! MAIN APP: Port registration result: $ok !!!');
    _port = port;
    port.listen((data) {
      print('!!! MAIN APP RECEIVED DATA: $data !!!');
      if (data is Map) _onOverlayMessage(Map<String, dynamic>.from(data));
    });

    _initTts();
  }

  /// Request mic permission and initialize speech_to_text.
  /// Safe to call repeatedly — only does the work once.
  Future<bool> requestPermissionAndInit() async {
    if (_initialized) return true;

    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      _send({'type': 'status', 'listening': false, 'available': false});
      return false;
    }

    final ok = await _stt.initialize(
      onError: (e) {
        debugPrint('SpeechBridge STT error: ${e.errorMsg}');
        _send({
          'type': 'status',
          'listening': false,
          'available': true,
          'error': e.errorMsg,
        });
      },
      onStatus: (s) {
        debugPrint('SpeechBridge STT status: $s');
        _send({
          'type': 'status',
          'listening': _stt.isListening,
          'available': true,
        });
      },
    );

    print('SPEECH ENGINE READY: $ok');
    _initialized = ok;
    _send({'type': 'status', 'listening': false, 'available': ok});
    return ok;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Message handler
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _onOverlayMessage(Map<String, dynamic> data) async {
    final type = data['type'];
    switch (type) {
      // ── Speech control ──────────────────────────────────────────────────
      case 'start':
        if (!_initialized) {
          final ok = await requestPermissionAndInit();
          if (!ok) return;
        }
        // Reset guidance session when the user starts a new recording
        _currentGoal = '';
        _currentStep = 1;

        // Long listen/pause durations so the mic does NOT auto-stop after a
        // moment of silence — the user controls when to stop by tapping the
        // mic button again.
        await _stt.listen(
          onResult: _onResult,
          onSoundLevelChange: _onSoundLevel,
          listenFor: const Duration(minutes: 10),
          pauseFor: const Duration(minutes: 5),
          partialResults: true,
          cancelOnError: false,
          listenMode: ListenMode.dictation,
        );
        _send({'type': 'status', 'listening': true, 'available': true});
        break;

      case 'stop':
        await _stt.stop();
        _send({'type': 'status', 'listening': false, 'available': true});
        break;

      // ── AI guidance ─────────────────────────────────────────────────────
      case 'analyze':
        // Sent by overlay when the STT result is final.
        final text = (data['text'] as String?)?.trim() ?? '';
        if (text.isEmpty || _isAnalyzing) return;
        _currentGoal = text;
        _currentStep = 1;
        await _analyzeScreen();
        break;

      case 'next_step':
        // Sent by overlay when it detects that the screen changed after
        // the user followed an instruction.
        if (_currentGoal.isEmpty || _isAnalyzing) return;
        _currentStep++;
        await _analyzeScreen();
        break;

    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Core AI guidance loop
  // ─────────────────────────────────────────────────────────────────────────

  /// Takes a screenshot → calls Gemini Vision → speaks the instruction →
  /// sends the result (+ highlight coords) back to the overlay.
  Future<void> _analyzeScreen() async {
    print('!!! _analyzeScreen START goal="$_currentGoal" step=$_currentStep !!!');
    if (_currentGoal.isEmpty) {
      print('!!! _analyzeScreen ABORT: empty goal !!!');
      return;
    }
    _isAnalyzing = true;

    try {
      // 1. Hide the overlay UI BEFORE taking the screenshot, otherwise the AI
      // sees our own card ("Analyzing screen…") instead of the user's app.
      print('!!! hiding overlay for clean screenshot... !!!');
      _send({'type': 'hide'});
      await Future.delayed(const Duration(milliseconds: 250));

      // 2. Capture the screen (overlay is now invisible)
      print('!!! taking screenshot... !!!');
      final Uint8List? screenshot = await _takeScreenshot();
      print('!!! screenshot result: ${screenshot?.length ?? 0} bytes !!!');

      // 3. Bring the overlay back with the analyzing spinner
      _send({'type': 'analyzing', 'step': _currentStep});
      print('!!! sent analyzing message to overlay !!!');
      if (screenshot == null) {
        print('!!! screenshot is null — sending ai_error !!!');
        _send({
          'type': 'ai_error',
          'message': 'Could not capture the screen. Please try again.',
        });
        return;
      }

      // 2. Ask Gemini
      print('!!! calling Gemini... !!!');
      final step = await _aiService.analyzeScreenForGuidance(
        imageBytes: screenshot,
        userGoal: _currentGoal,
        currentStep: _currentStep,
      );
      print('!!! Gemini returned: instruction="${step.instruction}" '
          'highlight=${step.highlight} complete=${step.isComplete} !!!');

      // 3. Speak the instruction
      await _speak(step.instruction);

      // 4. Send to overlay.
      //
      // CRITICAL: We include the FULL screen logical dimensions so the overlay
      // can convert Gemini's screen-relative fractions into the overlay's local
      // coordinate space. The overlay only covers the bottom ~1150 px of the
      // screen — without this conversion, the highlight is drawn ~25% off.
      final view = PlatformDispatcher.instance.views.first;
      final screenW = view.physicalSize.width / view.devicePixelRatio;
      final screenH = view.physicalSize.height / view.devicePixelRatio;

      final Map<String, dynamic> msg = {
        'type': 'ai_step',
        'instruction': step.instruction,
        'step_number': step.stepNumber,
        'is_complete': step.isComplete,
        'screen_width': screenW,
        'screen_height': screenH,
      };
      if (step.highlight != null && !step.highlight!.isEmpty) {
        msg['highlight'] = {
          'x': step.highlight!.x,
          'y': step.highlight!.y,
          'w': step.highlight!.width,
          'h': step.highlight!.height,
        };
      }

      _send(msg);
      print('!!! sent ai_step message to overlay (screen=${screenW.toInt()}x${screenH.toInt()}) !!!');
    } catch (e, st) {
      print('!!! _analyzeScreen ERROR: $e !!!');
      print(st);
      _send({
        'type': 'ai_error',
        'message': 'Something went wrong. Please try again.',
      });
    } finally {
      _isAnalyzing = false;
      print('!!! _analyzeScreen END !!!');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TTS
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _initTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.42); // Slightly slower for elderly users
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  Future<void> _speak(String text) async {
    await _tts.stop(); // Cancel any previous speech
    await _tts.speak(text);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Screenshot  (native → MainActivity.kt)
  // ─────────────────────────────────────────────────────────────────────────

  /// Calls the native 'app/screenshot' channel.
  /// Returns null if MediaProjection is not yet set up in MainActivity.kt —
  /// in that case the caller shows an error to the user.
  Future<Uint8List?> _takeScreenshot() async {
    try {
      final result =
          await _screenshotChannel.invokeMethod<Uint8List>('takeScreenshot');
      return result;
    } on PlatformException catch (e) {
      debugPrint('Screenshot PlatformException: ${e.code} — ${e.message}');
      return null;
    } catch (e) {
      debugPrint('Screenshot error: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STT callbacks
  // ─────────────────────────────────────────────────────────────────────────

  void _onResult(SpeechRecognitionResult result) {
    debugPrint('Main App recognized: ${result.recognizedWords}');
    _send({
      'type': 'words',
      'text': result.recognizedWords,
      'final': result.finalResult,
    });
  }

  /// Normalises the raw mic amplitude (-2 … 10 dB) to 0.0–1.0 and forwards
  /// it to the overlay so the listening indicator can pulse with the user's voice.
  void _onSoundLevel(double level) {
    const minDb = -2.0;
    const maxDb = 10.0;
    final normalized = ((level - minDb) / (maxDb - minDb)).clamp(0.0, 1.0);
    _send({'type': 'level', 'level': normalized});
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Port send helper
  // ─────────────────────────────────────────────────────────────────────────

  void _send(Map<String, dynamic> data) {
    final overlayPort = IsolateNameServer.lookupPortByName(overlayPortName);
    if (overlayPort == null) {
      debugPrint('SpeechBridge: overlay port not registered, dropping $data');
      return;
    }
    overlayPort.send(data);
  }
}

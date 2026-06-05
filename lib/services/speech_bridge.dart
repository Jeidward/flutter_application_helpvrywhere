import 'dart:async';
import 'dart:convert';
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

  // ── Native channels (implemented in MainActivity.kt) ───────────────────
  static const _screenshotChannel = MethodChannel('app/screenshot');
  static const _accessibilityChannel = MethodChannel('app/accessibility');

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
  // Instructions already given this session — passed to the AI so it can
  // detect loops and wrong-path situations.
  List<String> _stepHistory = [];


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
        await _stt.listen(
          onResult: _onResult,
          onSoundLevelChange: _onSoundLevel,
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
        _stepHistory = []; // fresh session — clear previous history
        await _analyzeScreen();
        break;

      case 'next_step':
        // Sent by overlay when it detects that the screen changed after
        // the user followed an instruction.
        if (_currentGoal.isEmpty || _isAnalyzing) return;
        _currentStep++;
        await _analyzeScreen();
        break;

      case 'close':
        // Sent by the overlay's X button or "Close Assistant" success
        // button. Tear down the session so the next time the user opens
        // the overlay they get a clean slate (no stale goal / step / TTS
        // still talking).
        try {
          await _stt.stop();
        } catch (_) {}
        try {
          await _tts.stop();
        } catch (_) {}
        _currentGoal = '';
        _currentStep = 1;
        _isAnalyzing = false;
        _stepHistory = [];
        debugPrint('SpeechBridge: session reset');
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
      await Future.delayed(const Duration(milliseconds: 80));

      // 2. Capture screenshot + UI tree at nearly the same instant so they
      //    describe the same UI state. The original screenshot is kept for
      //    high-quality cropping; a resized copy goes to the AI for speed.
      print('!!! taking screenshot + ui tree... !!!');
      final original = await _takeScreenshot();
      final uiTree = await _getUiTree();
      print('!!! ui tree size: ${uiTree.length} elements !!!');

      Uint8List? aiImage;
      if (original != null) {
        aiImage = await _resizeScreenshot(original) ?? original;
      }
      print('!!! screenshot result: ${aiImage?.length ?? 0} bytes !!!');

      // 3. Bring the overlay back with the analyzing spinner
      _send({'type': 'analyzing', 'step': _currentStep});
      print('!!! sent analyzing message to overlay !!!');
      if (aiImage == null) {
        print('!!! screenshot is null — sending ai_error !!!');
        _send({
          'type': 'ai_error',
          'message': 'Could not capture the screen. Please try again.',
        });
        return;
      }

      // Filter to keep the prompt small. Keep at most 60 elements, prefer
      // clickable ones, drop tiny non-text elements that just add noise.
      final filteredTree = _filterTree(uiTree);
      print('!!! filtered tree: ${filteredTree.length} elements !!!');

      // 4. Ask Groq — include step history AND the (possibly empty) tree.
      print('!!! calling Groq... !!!');
      final step = await _aiService.analyzeScreenForGuidance(
        imageBytes: aiImage,
        userGoal: _currentGoal,
        currentStep: _currentStep,
        stepHistory: List.from(_stepHistory),
        uiTree: filteredTree,
      );
      print('!!! Groq returned: instruction="${step.instruction}" '
          'complete=${step.isComplete} targetId=${step.targetId} !!!');

      // 5. Append instruction to history (capped at 5) so future steps have
      //    context for loop and wrong-path detection.
      if (!step.isComplete) {
        _stepHistory.add(step.instruction);
        if (_stepHistory.length > 5) _stepHistory.removeAt(0);
      }

      // 6. Crop the thumbnail. Two paths:
      //    a) Preferred: AI picked a target_id → crop the ORIGINAL screenshot
      //       at the OS-provided pixel bounds. Always accurate.
      //    b) Fallback: AI returned a target_region bbox → crop the resized
      //       image at the normalized region. Imprecise but better than nothing.
      String? thumbnailBase64;
      if (!step.isComplete) {
        Uint8List? thumb;
        if (step.targetId != null &&
            step.targetId! >= 0 &&
            step.targetId! < filteredTree.length &&
            original != null) {
          final el = filteredTree[step.targetId!];
          thumb = await _cropPixels(original, el.x, el.y, el.width, el.height);
          if (thumb != null) {
            print('!!! thumbnail cropped via tree id=${el.id} '
                'at (${el.x},${el.y}) ${el.width}x${el.height} '
                '→ ${thumb.length} bytes !!!');
          }
        } else if (step.targetRegion != null && !step.targetRegion!.isUseless) {
          thumb = await _cropRegion(aiImage, step.targetRegion!);
          if (thumb != null) {
            print('!!! thumbnail cropped via bbox fallback: '
                '${thumb.length} bytes !!!');
          }
        }
        if (thumb != null) {
          thumbnailBase64 = base64Encode(thumb);
        }
      }

      // 5. Send to overlay FIRST — the text appears immediately while TTS
      //    is still warming up. This eliminates the "blank wait" the user
      //    experienced between the spinner disappearing and anything showing.
      final Map<String, dynamic> msg = {
        'type': 'ai_step',
        'instruction': step.instruction,
        'step_number': step.stepNumber,
        'is_complete': step.isComplete,
        if (thumbnailBase64 != null) 'thumbnail': thumbnailBase64,
      };
      _send(msg);

      // 4. Speak in parallel — fire-and-forget so the overlay is already
      //    updated by the time the first word is spoken.
      unawaited(_speak(step.instruction));
      print('!!! sent ai_step message to overlay !!!');
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
  // Accessibility (UI tree)  — exposed publicly for the onboarding flow
  // ─────────────────────────────────────────────────────────────────────────

  /// Is the user's accessibility service for our app currently enabled?
  /// False when permission was never granted OR the user turned it off.
  Future<bool> isAccessibilityEnabled() async {
    try {
      final v = await _accessibilityChannel
          .invokeMethod<bool>('isAccessibilityEnabled');
      return v ?? false;
    } catch (e) {
      debugPrint('isAccessibilityEnabled error: $e');
      return false;
    }
  }

  /// Opens the system's accessibility settings page so the user can
  /// enable HelpEverywhere's service.
  Future<void> openAccessibilitySettings() async {
    try {
      await _accessibilityChannel.invokeMethod('openAccessibilitySettings');
    } catch (e) {
      debugPrint('openAccessibilitySettings error: $e');
    }
  }

  /// Fetch the active window's UI tree. Returns [] when the service is
  /// off, the current app blocks accessibility, or any error occurs.
  Future<List<UiElement>> _getUiTree() async {
    try {
      final raw = await _accessibilityChannel.invokeMethod('getUiTree');
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((m) => UiElement.fromMap(m))
          .toList(growable: false);
    } catch (e) {
      debugPrint('_getUiTree error: $e');
      return const [];
    }
  }

  /// Trim the raw tree down to what's actually useful for the AI:
  /// drop tiny non-text leaves that just bloat the prompt, cap the
  /// total at 60 entries, and renumber sequentially (so target_id
  /// indexes the returned list directly).
  List<UiElement> _filterTree(List<UiElement> raw) {
    final keep = <UiElement>[];
    for (final e in raw) {
      final hasLabel = e.text != null || e.description != null;
      final bigEnough = e.width >= 24 && e.height >= 24;
      // Keep anything with a label; for unlabeled elements require a
      // clickable hit area of at least 24×24 (typical icon button size).
      if (hasLabel || (e.clickable && bigEnough)) {
        keep.add(e);
      }
    }
    if (keep.length <= 60) {
      return _renumber(keep);
    }
    // Too many — keep clickable + labeled first, then largest.
    keep.sort((a, b) {
      final aScore = (a.clickable ? 2 : 0) + (a.text != null ? 1 : 0);
      final bScore = (b.clickable ? 2 : 0) + (b.text != null ? 1 : 0);
      if (aScore != bScore) return bScore.compareTo(aScore);
      return (b.width * b.height).compareTo(a.width * a.height);
    });
    return _renumber(keep.take(60).toList());
  }

  List<UiElement> _renumber(List<UiElement> els) => [
        for (var i = 0; i < els.length; i++)
          UiElement(
            id: i,
            text: els[i].text,
            description: els[i].description,
            className: els[i].className,
            clickable: els[i].clickable,
            x: els[i].x,
            y: els[i].y,
            width: els[i].width,
            height: els[i].height,
          ),
      ];

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

  /// Resize the screenshot to ≤720px wide and re-encode as PNG.
  /// Half the resolution → roughly ¼ the data → noticeably faster base64
  /// encode + upload to Gemini. Returns null on failure; caller falls back
  /// to the original bytes.
  Future<Uint8List?> _resizeScreenshot(Uint8List imageBytes) async {
    try {
      final codec = await instantiateImageCodec(imageBytes, targetWidth: 720);
      final frame = await codec.getNextFrame();
      final byteData = await frame.image.toByteData(
        format: ImageByteFormat.png,
      );
      frame.image.dispose();
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('Screenshot resize failed: $e');
      return null;
    }
  }

  /// Crop the source image to an absolute pixel rectangle, with 15%
  /// padding on each side for visual context. Used when the AI picked
  /// an element from the UI tree (so coords are perfect).
  Future<Uint8List?> _cropPixels(
    Uint8List imageBytes,
    int x,
    int y,
    int w,
    int h,
  ) async {
    try {
      final codec = await instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      final src = frame.image;

      final padX = w * 0.15;
      final padY = h * 0.15;
      final left = (x - padX).clamp(0.0, src.width.toDouble());
      final top = (y - padY).clamp(0.0, src.height.toDouble());
      final right = (x + w + padX).clamp(0.0, src.width.toDouble());
      final bottom = (y + h + padY).clamp(0.0, src.height.toDouble());

      final cropW = (right - left).round();
      final cropH = (bottom - top).round();
      if (cropW < 16 || cropH < 16) {
        src.dispose();
        return null;
      }

      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        src,
        Rect.fromLTRB(left, top, right, bottom),
        Rect.fromLTWH(0, 0, cropW.toDouble(), cropH.toDouble()),
        Paint(),
      );
      final picture = recorder.endRecording();
      final cropped = await picture.toImage(cropW, cropH);
      final byteData = await cropped.toByteData(format: ImageByteFormat.png);

      src.dispose();
      cropped.dispose();
      picture.dispose();
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('_cropPixels failed: $e');
      return null;
    }
  }

  /// Crop the screenshot to the region the AI identified, with a bit of
  /// extra padding so the target element is comfortably included even if
  /// the model's coordinates are slightly off. Encoded as PNG.
  /// Returns null on any failure; the overlay falls back to text-only.
  Future<Uint8List?> _cropRegion(
    Uint8List imageBytes,
    TargetRegion region,
  ) async {
    try {
      final codec = await instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      final src = frame.image;

      // Add 15% padding around the region so a slightly-off bbox still
      // contains the actual element.
      final padX = region.width * 0.15;
      final padY = region.height * 0.15;
      final left = ((region.x - padX) * src.width).clamp(0.0, src.width.toDouble());
      final top = ((region.y - padY) * src.height).clamp(0.0, src.height.toDouble());
      final right = ((region.x + region.width + padX) * src.width)
          .clamp(0.0, src.width.toDouble());
      final bottom = ((region.y + region.height + padY) * src.height)
          .clamp(0.0, src.height.toDouble());

      final cropW = (right - left).round();
      final cropH = (bottom - top).round();

      if (cropW < 16 || cropH < 16) {
        src.dispose();
        debugPrint('Crop region too small: ${cropW}x$cropH — skipping');
        return null;
      }

      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        src,
        Rect.fromLTRB(left, top, right, bottom),
        Rect.fromLTWH(0, 0, cropW.toDouble(), cropH.toDouble()),
        Paint(),
      );
      final picture = recorder.endRecording();
      final cropped = await picture.toImage(cropW, cropH);
      final byteData = await cropped.toByteData(format: ImageByteFormat.png);

      src.dispose();
      cropped.dispose();
      picture.dispose();

      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('Crop failed: $e');
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

  /// Forward mic amplitude to the overlay so the listening indicator can
  /// react to the user's voice. speech_to_text reports a roughly -2..10 dB
  /// range (platform-dependent); we normalize to 0..1 here so the overlay
  /// doesn't have to know the underlying scale.
  void _onSoundLevel(double level) {
    const minLevel = -2.0;
    const maxLevel = 10.0;
    final normalized =
        ((level - minLevel) / (maxLevel - minLevel)).clamp(0.0, 1.0);
    _send({'type': 'level', 'level': normalized});
  }

  void _send(Map<String, dynamic> data) {
    final overlayPort = IsolateNameServer.lookupPortByName(overlayPortName);
    if (overlayPort == null) {
      debugPrint('SpeechBridge: overlay port not registered, dropping $data');
      return;
    }
    overlayPort.send(data);
  }
}

import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Owns the SpeechToText plugin in the MAIN app isolate, where an Activity
/// context exists. The overlay (separate Flutter engine, attached to a
/// Service) cannot use the plugin directly.
///
/// We bridge the two isolates with `IsolateNameServer` ports because
/// `flutter_overlay_window` 0.4.5 has a broken overlay→main channel —
/// `shareData` from the overlay never reaches the main app's listener.
///
/// Wire protocol (Map<String, ...>):
///   overlay → main:  {'type': 'start'} | {'type': 'stop'}
///   main → overlay:  {'type': 'status', 'listening': bool, 'available': bool}
///                    {'type': 'words',  'text': String, 'final': bool}
class SpeechBridge {
  SpeechBridge._();
  static final SpeechBridge instance = SpeechBridge._();

  /// Port name the OVERLAY isolate looks up to send commands to MAIN.
  static const String mainPortName = 'speech_bridge.main';

  /// Port name the MAIN isolate looks up to send results back to OVERLAY.
  static const String overlayPortName = 'speech_bridge.overlay';

  final SpeechToText _stt = SpeechToText();
  ReceivePort? _port;
  bool _initialized = false;

  /// Subscribe to overlay messages. Call once at app startup.
  void registerOverlayListener() {
    if (_port != null) return;
    print("!!! MAIN APP: Registering IsolateNameServer port NOW !!!");
    // Clear any stale port from a previous run/hot-restart.
    IsolateNameServer.removePortNameMapping(mainPortName);
    final port = ReceivePort();
    final ok =
        IsolateNameServer.registerPortWithName(port.sendPort, mainPortName);
    print("!!! MAIN APP: Port registration result: $ok !!!");
    _port = port;
    port.listen((data) {
      print("!!! MAIN APP RECEIVED DATA: $data !!!");
      if (data is Map) _onOverlayMessage(Map<String, dynamic>.from(data));
    });
  }

  /// Request mic permission and initialize speech_to_text. Safe to call
  /// repeatedly — only does the work once. Call this from a screen with
  /// an Activity context (e.g. before showing the overlay).
  Future<bool> requestPermissionAndInit() async {
    if (_initialized) return true;

    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      _send({'type': 'status', 'listening': false, 'available': false});
      return false;
    }

    final ok = await _stt.initialize(
      onError: (e) {
        debugPrint('SpeechBridge error: ${e.errorMsg}');
        _send({
          'type': 'status',
          'listening': false,
          'available': true,
          'error': e.errorMsg,
        });
      },
      onStatus: (s) {
        debugPrint('SpeechBridge status: $s');
        _send({
          'type': 'status',
          'listening': _stt.isListening,
          'available': true,
        });
      },
    );

    print("SPEECH ENGINE READY: $ok");
    _initialized = ok;
    _send({'type': 'status', 'listening': false, 'available': ok});
    return ok;
  }

  Future<void> _onOverlayMessage(Map<String, dynamic> data) async {
    final type = data['type'];
    switch (type) {
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
    }
  }

  void _onResult(SpeechRecognitionResult result) {
    debugPrint("Main App recognized: ${result.recognizedWords}");
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
      debugPrint("SpeechBridge: overlay port not registered, dropping $data");
      return;
    }
    overlayPort.send(data);
  }
}

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

// ── Data classes ─────────────────────────────────────────────────────────────

/// One guidance step returned by the AI for the overlay loop.
class AiStep {
  final String instruction; // What the user must do — read aloud by TTS
  final bool isComplete; // true = goal reached, close the overlay
  final int stepNumber;
  /// Index into the UI tree the AI was shown. SpeechBridge uses this to
  /// look up the element's exact pixel bounds from AccessibilityService.
  /// Null/negative when the model didn't pick a tree element (no tree
  /// available, no match, system gesture, or goal complete).
  final int? targetId;
  /// Normalized region (0–1) fallback — used when no UI tree was available
  /// (accessibility service off) so we still get *some* thumbnail.
  /// Null when complete or when the model didn't return one.
  final TargetRegion? targetRegion;

  const AiStep({
    required this.instruction,
    required this.isComplete,
    this.stepNumber = 1,
    this.targetId,
    this.targetRegion,
  });

  factory AiStep.fromJson(Map<String, dynamic> json) {
    final rawId = json['target_id'];
    int? id;
    if (rawId is int && rawId >= 0) {
      id = rawId;
    } else if (rawId is num && rawId >= 0) {
      id = rawId.toInt();
    }

    TargetRegion? region;
    final regionRaw = json['target_region'];
    if (regionRaw is Map) {
      try {
        region = TargetRegion.fromJson(Map<String, dynamic>.from(regionRaw));
      } catch (_) {
        region = null;
      }
    }
    return AiStep(
      instruction:
          (json['instruction'] as String?)?.trim() ??
          'Follow the instructions on screen.',
      isComplete: json['is_complete'] as bool? ?? false,
      stepNumber: json['step_number'] as int? ?? 1,
      targetId: id,
      targetRegion: region,
    );
  }

  factory AiStep.error(String message) {
    return AiStep(instruction: message, isComplete: false);
  }
}

/// One element from the OS-provided UI tree. We hand a filtered list of
/// these to the model so it can pick a target by id instead of guessing
/// pixel coordinates.
class UiElement {
  final int id;
  final String? text;
  final String? description;
  final String? className;
  final bool clickable;
  final int x;
  final int y;
  final int width;
  final int height;

  const UiElement({
    required this.id,
    required this.text,
    required this.description,
    required this.className,
    required this.clickable,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory UiElement.fromMap(Map<dynamic, dynamic> m) => UiElement(
        id: (m['id'] as num).toInt(),
        text: (m['text'] as String?)?.trim().isNotEmpty == true
            ? (m['text'] as String).trim()
            : null,
        description: (m['description'] as String?)?.trim().isNotEmpty == true
            ? (m['description'] as String).trim()
            : null,
        className: m['class'] as String?,
        clickable: m['clickable'] == true,
        x: (m['x'] as num).toInt(),
        y: (m['y'] as num).toInt(),
        width: (m['width'] as num).toInt(),
        height: (m['height'] as num).toInt(),
      );

  /// Compact single-line representation for the prompt.
  /// Format:  [42] Button "YouTube" desc="Open YouTube" at (650,1800) 120x120
  String toPromptLine() {
    final parts = <String>['[$id]'];
    if (className != null) parts.add(className!);
    if (text != null) parts.add('"$text"');
    if (description != null && description != text) {
      parts.add('desc="$description"');
    }
    if (clickable) parts.add('(clickable)');
    parts.add('at ($x,$y) ${width}x$height');
    return parts.join(' ');
  }
}

/// Normalized region (0.0–1.0) returned by the model. (0,0) is the top-left
/// of the screenshot, (1,1) is the bottom-right. Width and height are also
/// fractions of the full image size.
class TargetRegion {
  final double x;
  final double y;
  final double width;
  final double height;

  const TargetRegion({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory TargetRegion.fromJson(Map<String, dynamic> json) {
    double parse(dynamic v, double fallback) =>
        v is num ? v.toDouble() : fallback;
    final x = parse(json['x'], 0.0).clamp(0.0, 1.0).toDouble();
    final y = parse(json['y'], 0.0).clamp(0.0, 1.0).toDouble();
    final w = parse(json['width'], 1.0).clamp(0.01, 1.0).toDouble();
    final h = parse(json['height'], 1.0).clamp(0.01, 1.0).toDouble();
    return TargetRegion(x: x, y: y, width: w, height: h);
  }

  /// True when the region is either too small or essentially the whole
  /// screen — both useless for a thumbnail, so we skip the crop.
  bool get isUseless =>
      width >= 0.95 || height >= 0.95 || width <= 0.02 || height <= 0.02;

  @override
  String toString() =>
      '(x: ${x.toStringAsFixed(2)}, y: ${y.toStringAsFixed(2)}, '
      'w: ${width.toStringAsFixed(2)}, h: ${height.toStringAsFixed(2)})';
}

// ── Service ───────────────────────────────────────────────────────────────────

class AiService {
  // Groq key loaded from `.env` (gitignored). Add: GROQ_KEY=gsk_...
  static String get _apiKey => dotenv.env['GROQ_KEY'] ?? '';

  // Llama 4 Scout on Groq — vision support + extremely fast LPU inference.
  static const String _model = 'meta-llama/llama-4-scout-17b-16e-instruct';
  static const String _apiUrl =
      'https://api.groq.com/openai/v1/chat/completions';

  // ── Overlay guidance loop ─────────────────────────────────────────────────

  /// Takes a screenshot + the user's spoken goal and returns one guidance
  /// step. Call again with a fresh screenshot after every user action.
  Future<AiStep> analyzeScreenForGuidance({
    required Uint8List imageBytes,
    required String userGoal,
    int currentStep = 1,
    List<String> stepHistory = const [],
    List<UiElement> uiTree = const [],
  }) async {
    final base64Image = base64Encode(imageBytes);

    // Format the step history for the prompt.
    final historyText = stepHistory.isEmpty
        ? 'None — this is the first step.'
        : stepHistory
            .asMap()
            .entries
            .map((e) => '  Step ${e.key + 1}: "${e.value}"')
            .join('\n');

    final lastInstruction =
        stepHistory.isNotEmpty ? stepHistory.last : 'none yet';

    // UI tree section — present only when AccessibilityService is enabled.
    // When present, the model should pick a target_id from this list (the
    // OS-provided bounds are perfect). When absent, the model falls back
    // to target_region (a normalized bbox it guesses from the screenshot).
    final hasTree = uiTree.isNotEmpty;
    final treeText = hasTree
        ? uiTree.map((e) => '  ${e.toPromptLine()}').join('\n')
        : '  (UI tree not available — accessibility service is off)';

    final prompt = '''
You are an AI assistant helping elderly users (65+) use their smartphone.

The user's goal is: "$userGoal"
This is step $currentStep.

── What you already told the user ───────────────────────────────────────────
$historyText

── UI elements currently on screen (from the OS, with EXACT pixel coords) ──
$treeText

══════════════════════════════════════════════════════════════════════════════
GOAL COMPLETION — Take the user's goal LITERALLY. Do NOT add extra steps.
══════════════════════════════════════════════════════════════════════════════

"open X"
  → DONE the moment X is visible on screen.
  → Do NOT suggest searching, scrolling, tapping videos, or anything else.
    The user only asked to OPEN it. Stop there.
  → Examples:
    • "open YouTube"  → YouTube interface visible (red logo + video feed) → DONE.
    • "open Gmail"    → Gmail inbox visible → DONE.
    • "open Settings" → Settings menu visible → DONE.
    • "open WhatsApp" → WhatsApp chat list visible → DONE.

"send a message to X"  → DONE when the message appears as "Sent" in the chat thread.
"call X"               → DONE when the dialing / call-active screen shows X.
"take a photo"         → DONE when the photo preview is shown.
"search for Y"         → DONE when Y appears in search results.

══════════════════════════════════════════════════════════════════════════════
PROBLEM DETECTION
══════════════════════════════════════════════════════════════════════════════

LOOP — The last instruction was: "$lastInstruction"
  If the screen looks the same and you would repeat that instruction → DO NOT.
  Give a completely different action (Back button, home screen, scroll, etc.).

WRONG SCREEN — If the user is in an app/screen that cannot reach "$userGoal":
  Tell them: "You went to the wrong app. Press the back button at the very bottom of the screen to return."

STUCK — If the same instruction appears twice in history → try a different approach.

══════════════════════════════════════════════════════════════════════════════
RESPONSE FORMAT — ONLY this JSON, no markdown, no extra text
══════════════════════════════════════════════════════════════════════════════

{
  "what_i_see": "1 honest sentence describing the screen. Name the app if you can identify it.",
  "is_complete": <true or false>,
  "instruction": "...",
  "target_id": -1,
  "target_region": {"x": 0.0, "y": 0.0, "width": 1.0, "height": 1.0},
  "step_number": $currentStep
}

IMPORTANT: Fill "what_i_see" FIRST. Identifying the screen helps you decide is_complete correctly.
Apply the GOAL COMPLETION rules above strictly — if "what_i_see" describes the goal already achieved, is_complete MUST be true.

Rules for "instruction":
- is_complete TRUE  → "Great! You reached your goal. You can close the assistant."
- is_complete FALSE → ONE action only. Describe by COLOR, SHAPE, POSITION. Max 30 words.
    GOOD: "Tap the red square with a white play button near the bottom right — labeled YouTube."
    BAD:  "Tap the YouTube icon."

Rules for "target_id" (preferred when the UI tree above has elements):
- Pick the ID of the element the user should tap from the list above.
- Match by text, description, class, and what you see in the screenshot.
- If multiple elements could match, prefer the most CLICKABLE one (clickable=true).
- If NOTHING in the list matches → return -1.
- If is_complete is TRUE → return -1.
- If the action is a system gesture (back, home, swipe) → return -1.

Rules for "target_region" (fallback — only used when target_id is -1):
- (0,0) is the TOP-LEFT of the screenshot. (1,1) is the BOTTOM-RIGHT.
- x, y, width, height frame the target element with some context (≈1.5x).
- When target_id is a valid ID, set this to {"x": 0, "y": 0, "width": 1, "height": 1}.
- When is_complete or system gesture, also return the full-screen default.
''';

    final body = jsonEncode({
      'model': _model,
      'messages': [
        {
          'role': 'user',
          'content': [
            {
              'type': 'image_url',
              'image_url': {'url': 'data:image/png;base64,$base64Image'},
            },
            {'type': 'text', 'text': prompt},
          ],
        },
      ],
      'max_tokens': 300, // covers what_i_see + target_id + target_region
      'temperature': 0.0, // deterministic — no creativity for UI guidance
      'response_format': {'type': 'json_object'}, // guaranteed JSON output
    });

    const transientCodes = {408, 429, 500, 502, 503, 504};
    http.Response? response;

    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        response = await http
            .post(
              Uri.parse(_apiUrl),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $_apiKey',
              },
              body: body,
            )
            .timeout(
              const Duration(seconds: 30),
              onTimeout: () => http.Response('{"error":"timeout"}', 408),
            );

        if (!transientCodes.contains(response.statusCode)) break;

        print(
          '=== GROQ transient error ${response.statusCode} '
          '(attempt ${attempt + 1}/3) — retrying ===',
        );
      } catch (e) {
        print('=== AI SERVICE EXCEPTION (attempt ${attempt + 1}/3): $e ===');
        if (e.toString().contains('SocketException')) {
          return AiStep.error(
            'No internet connection. Please check your WiFi and try again.',
          );
        }
      }

      if (attempt < 2) {
        await Future.delayed(Duration(seconds: 1 << attempt));
      }
    }

    if (response == null) {
      return AiStep.error('Network error. Please try again.');
    }

    if (response.statusCode == 200) {
      return _parseGroqGuidanceResponse(response.body);
    }

    print('=== GROQ ERROR after retries [analyzeScreenForGuidance] ===');
    print('Status: ${response.statusCode}');
    print('Body: ${response.body}');

    if (response.statusCode == 400) {
      return AiStep.error(
        'AI rejected the request (400). Check the terminal for details.',
      );
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      return AiStep.error('AI key is invalid or unauthorized.');
    }
    return AiStep.error('Could not analyze the screen. Please try again.');
  }

  /// Parse Groq's OpenAI-compatible JSON response.
  AiStep _parseGroqGuidanceResponse(String responseBody) {
    try {
      final data = jsonDecode(responseBody) as Map<String, dynamic>;

      final choices = data['choices'];
      if (choices is! List || choices.isEmpty) {
        print('=== GROQ: no choices in response. Body: $responseBody ===');
        return AiStep.error('Could not analyze the screen. Please try again.');
      }

      final finishReason = choices[0]['finish_reason'] as String?;
      final content = choices[0]['message']?['content'] as String?;

      if (content == null || content.trim().isEmpty) {
        print('=== GROQ: empty content (finish_reason=$finishReason) ===');
        return AiStep.error('AI returned no answer. Please try again.');
      }

      // response_format: json_object guarantees valid JSON, but clean just in case.
      var cleaned = content
          .trim()
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();

      final firstBrace = cleaned.indexOf('{');
      final lastBrace = cleaned.lastIndexOf('}');
      if (firstBrace >= 0 && lastBrace > firstBrace) {
        cleaned = cleaned.substring(firstBrace, lastBrace + 1);
      }

      final jsonMap = jsonDecode(cleaned) as Map<String, dynamic>;

      // Log the model's screen identification — invaluable for debugging
      // why is_complete didn't trigger when it should have.
      final whatISee = jsonMap['what_i_see'];
      if (whatISee != null) {
        print('=== GROQ sees: "$whatISee" ===');
      }
      final idLog = jsonMap['target_id'];
      if (idLog != null) {
        print('=== GROQ target_id: $idLog ===');
      }
      final regionLog = jsonMap['target_region'];
      if (regionLog != null) {
        print('=== GROQ target_region: $regionLog ===');
      }

      return AiStep.fromJson(jsonMap);
    } catch (e) {
      print('=== GROQ parse failed: $e ===');
      print('Body: $responseBody');
      return AiStep.error('AI gave a confusing answer. Please try again.');
    }
  }

  // ── Manual image-picker flow (AIGuideScreen) ──────────────────────────────

  Future<List<String>> analyzeScreenAndGuide({
    required Uint8List imageBytes,
    required String userGoal,
  }) async {
    final base64Image = base64Encode(imageBytes);

    try {
      final response = await http
          .post(
            Uri.parse(_apiUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_apiKey',
            },
            body: jsonEncode({
              'model': _model,
              'messages': [
                {
                  'role': 'user',
                  'content': [
                    {
                      'type': 'image_url',
                      'image_url': {
                        'url': 'data:image/png;base64,$base64Image',
                      },
                    },
                    {
                      'type': 'text',
                      'text':
                          'You are a technology assistant helping elderly users (65+) '
                          'use their smartphones.\n\n'
                          'The user wants to: "$userGoal"\n\n'
                          'Analyze what is visible on the screen and provide clear '
                          'step-by-step instructions. Use very simple language — '
                          'describe elements by their COLOR and SHAPE.\n'
                          'BAD: "Tap the WhatsApp icon"\n'
                          'GOOD: "Find the green square with a white phone inside"\n\n'
                          'Reply ONLY with a numbered list, max 5 steps:\n'
                          '1. [instruction]\n2. [instruction]\n3. [instruction]',
                    },
                  ],
                },
              ],
              'max_tokens': 500,
              'temperature': 0.3,
            }),
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => http.Response('{"error":"timeout"}', 408),
          );

      if (response.statusCode == 200) {
        final text = _extractText(response.body);
        if (text == null) return ['Could not analyze the image. Please try again.'];
        return _parseSteps(text);
      }

      print('=== GROQ ERROR [analyzeScreenAndGuide] ===');
      print('Status: ${response.statusCode} | Body: ${response.body}');
      return ['Error ${response.statusCode}. Check the terminal for details.'];
    } catch (e) {
      print('=== EXCEPTION: $e ===');
      if (e.toString().contains('SocketException') ||
          e.toString().contains('timeout')) {
        return ['No internet connection. Please check your WiFi and try again.'];
      }
      return ['Unexpected error: ${e.toString()}'];
    }
  }

  // ── Text-only quick help ──────────────────────────────────────────────────

  Future<String> quickHelp(String question) async {
    try {
      final response = await http
          .post(
            Uri.parse(_apiUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_apiKey',
            },
            body: jsonEncode({
              'model': _model,
              'messages': [
                {
                  'role': 'user',
                  'content':
                      'You are a technology assistant for elderly users. '
                      'Answer in very simple language, max 3 short sentences: '
                      '"$question"',
                },
              ],
              'max_tokens': 200,
              'temperature': 0.3,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return _extractText(response.body) ??
            'Could not get a response. Please try again.';
      }
      return 'Could not get a response. Please try again.';
    } catch (_) {
      return 'No connection. Check your internet and try again.';
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Extract the assistant's text from Groq's OpenAI-compatible response.
  String? _extractText(String responseBody) {
    try {
      final data = jsonDecode(responseBody);
      final choices = data['choices'];
      if (choices is! List || choices.isEmpty) return null;
      final content = choices[0]['message']?['content'] as String?;
      if (content == null || content.trim().isEmpty) return null;
      return content.trim();
    } catch (_) {
      return null;
    }
  }

  List<String> _parseSteps(String rawText) {
    final lines = rawText.trim().split('\n');
    final steps = <String>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final cleaned = trimmed.replaceFirst(RegExp(r'^\d+[\.\)]\s*'), '');
      if (cleaned.isNotEmpty) steps.add(cleaned);
    }
    if (steps.isEmpty) {
      return ['Could not analyze the image. Please try with a clearer photo.'];
    }
    return steps;
  }
}

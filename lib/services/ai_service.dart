import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

// ── Data classes ────────────────────────────────────────────────────────────

/// Coordinates of the element the user must tap, expressed as fractions
/// of the full screen size (0.0 → 1.0). x/y = top-left corner.
class HighlightRect {
  final double x;
  final double y;
  final double width;
  final double height;

  const HighlightRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory HighlightRect.fromJson(Map<String, dynamic> json) {
    return HighlightRect(
      x: (json['x'] as num).toDouble().clamp(0.0, 1.0),
      y: (json['y'] as num).toDouble().clamp(0.0, 1.0),
      width: (json['w'] as num).toDouble().clamp(0.0, 1.0),
      height: (json['h'] as num).toDouble().clamp(0.0, 1.0),
    );
  }

  /// Returns true when the highlight covers no meaningful area (e.g. element
  /// not visible on screen or goal already complete).
  bool get isEmpty => width == 0 && height == 0;
}

/// One guidance step returned by Gemini for the overlay loop.
class AiStep {
  final String instruction; // What the user must do — read aloud by TTS
  final HighlightRect? highlight; // Element to highlight on screen (nullable)
  final bool isComplete; // true = goal reached, close the overlay
  final int stepNumber;

  const AiStep({
    required this.instruction,
    this.highlight,
    required this.isComplete,
    this.stepNumber = 1,
  });

  factory AiStep.fromJson(Map<String, dynamic> json) {
    final rawHighlight = json['highlight'];
    return AiStep(
      instruction: (json['instruction'] as String?)?.trim() ??
          'Follow the instructions on screen.',
      highlight: (rawHighlight is Map<String, dynamic>)
          ? HighlightRect.fromJson(rawHighlight)
          : null,
      isComplete: json['is_complete'] as bool? ?? false,
      stepNumber: json['step_number'] as int? ?? 1,
    );
  }

  /// Fallback when JSON parsing fails — plain text, no highlight.
  factory AiStep.error(String message) {
    return AiStep(instruction: message, isComplete: false);
  }
}

// ── Service ─────────────────────────────────────────────────────────────────

class AiService {
  // TODO: replace with your real key before demoing
  static const String _apiKey = '';
  // 2.5-flash is the one that worked initially — sticking with it.
  // If you see 503 (overloaded), the retry logic in this file will handle it.
  static const String _model = 'gemini-2.5-flash';

  static String get _apiUrl =>
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent?key=$_apiKey';

  // ── NEW: Overlay guidance loop ────────────────────────────────────────────

  /// Takes a screenshot + the user's spoken goal and returns one guidance
  /// step with a plain-language instruction AND the bounding box of the
  /// element the user must tap (as screen-size fractions 0.0–1.0).
  ///
  /// Call this again with a fresh screenshot after every user action to
  /// advance through the steps automatically.
  Future<AiStep> analyzeScreenForGuidance({
    required Uint8List imageBytes,
    required String userGoal,
    int currentStep = 1,
  }) async {
    final base64Image = base64Encode(imageBytes);

    final prompt = '''
You are an AI assistant helping elderly users (65+) use their smartphone.

The user's goal is: "$userGoal"
This is step $currentStep of the guidance session.

Analyze the screenshot CAREFULLY. Respond with ONLY a raw JSON object —
no markdown, no code blocks, no preamble like "Here is the JSON".

Required format:
{
  "instruction": "...",
  "highlight": { "x": 0.0, "y": 0.0, "w": 0.0, "h": 0.0 },
  "is_complete": false,
  "step_number": $currentStep
}

── Field rules ────────────────────────────────────────────────────────

"instruction"
  - ONE action, described using COLOR and SHAPE (NOT brand names).
  - Position must be CONSISTENT with the highlight coordinates.
    If your highlight is at y > 0.7, say "near the bottom" — NOT "top".
    If your highlight is at x > 0.7, say "right side" — NOT "left".
  - Maximum 25 words. Simple language for elderly users.

"highlight" — bounding box of the element to tap.
  Coordinates are FRACTIONS OF THE FULL SCREENSHOT (0.0 to 1.0):
    x = fraction from the LEFT edge   (0.0 = far left, 1.0 = far right)
    y = fraction from the TOP edge    (0.0 = very top, 1.0 = very bottom)
    w = width  as fraction of screen
    h = height as fraction of screen
  Position guide:
    Status bar / clock     → y around 0.0–0.04
    Top of content          → y around 0.05–0.25
    Middle of screen        → y around 0.4–0.6
    Bottom dock / nav bar   → y around 0.85–0.98
  Be PRECISE. If the icon visually sits in the bottom row of app icons,
  y should be 0.85 or higher.
  If the element is not visible / no tap needed, use {"x":0,"y":0,"w":0,"h":0}.

"is_complete": true ONLY if the goal is already achieved in this screenshot.
  If true, set instruction to "You reached your goal! You can close the assistant."
''';

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {
              'inline_data': {
                'mime_type': 'image/jpeg',
                'data': base64Image,
              }
            },
            {'text': prompt},
          ]
        }
      ],
      'generationConfig': {
        'maxOutputTokens': 300,
        'temperature': 0.1,
        'responseMimeType': 'application/json',
      },
    });

    // Retry up to 3 times on transient failures (503/429/500/timeout) with
    // exponential backoff: 1s → 2s → 4s. Gemini's free tier returns 503 when
    // the model is hot — a couple of retries usually clears it.
    const transientCodes = {408, 429, 500, 502, 503, 504};
    http.Response? response;

    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        response = await http
            .post(
              Uri.parse(_apiUrl),
              headers: {'Content-Type': 'application/json'},
              body: body,
            )
            .timeout(
              const Duration(seconds: 30),
              onTimeout: () => http.Response('{"error":"timeout"}', 408),
            );

        // Success or non-retryable error → bail out
        if (!transientCodes.contains(response.statusCode)) break;

        print('=== GEMINI transient error ${response.statusCode} '
            '(attempt ${attempt + 1}/3) — retrying ===');
      } catch (e) {
        print('=== AI SERVICE EXCEPTION (attempt ${attempt + 1}/3): $e ===');
        if (e.toString().contains('SocketException')) {
          return AiStep.error(
              'No internet connection. Please check your WiFi and try again.');
        }
        // Other exceptions: treat as transient and retry
      }

      if (attempt < 2) {
        // 1s, then 2s — total worst case ≈ 4s wait
        await Future.delayed(Duration(seconds: 1 << attempt));
      }
    }

    if (response == null) {
      return AiStep.error('Network error. Please try again.');
    }

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final rawText =
          data['candidates'][0]['content']['parts'][0]['text'] as String;
      var cleaned = rawText
          .trim()
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();

      // Robust JSON extraction: Gemini sometimes prefaces the JSON with text
      // like "Here is the JSON requested:\n{...}". Slice everything between
      // the first `{` and the matching last `}` so we always parse pure JSON.
      final firstBrace = cleaned.indexOf('{');
      final lastBrace  = cleaned.lastIndexOf('}');
      if (firstBrace >= 0 && lastBrace > firstBrace) {
        cleaned = cleaned.substring(firstBrace, lastBrace + 1);
      }

      try {
        final jsonMap = jsonDecode(cleaned) as Map<String, dynamic>;
        return AiStep.fromJson(jsonMap);
      } catch (e) {
        print('=== JSON parse failed. Raw text: $rawText ===');
        return AiStep.error(
            'AI gave a confusing answer. Please try again.');
      }
    }

    print('=== GEMINI ERROR after retries [analyzeScreenForGuidance] ===');
    print('Status: ${response.statusCode}');
    print('Body: ${response.body}');

    // Generic error — don't try to interpret the cause for the user
    return AiStep.error(
        'Could not analyze the screen. Please try again.');
  }

  // ── EXISTING: kept for AIGuideScreen (manual image-picker flow) ───────────

  Future<List<String>> analyzeScreenAndGuide({
    required Uint8List imageBytes,
    required String userGoal,
  }) async {
    final base64Image = base64Encode(imageBytes);

    try {
      final response = await http
          .post(
            Uri.parse(_apiUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {
                      'inline_data': {
                        'mime_type': 'image/jpeg',
                        'data': base64Image,
                      }
                    },
                    {
                      'text':
                          '''You are a technology assistant helping elderly users (65+) use their smartphones.

The user wants to: "$userGoal"

This image is a screenshot from the user's phone.

Your task:
1. Analyze what is visible on the screen (apps, icons, buttons, menus).
2. Provide clear step-by-step instructions to help the user achieve their goal.
3. Use very simple language — describe elements by their COLOR and SHAPE, not their technical name.
   BAD example: "Tap the WhatsApp icon"
   GOOD example: "Find the green square with a white phone inside"

Reply ONLY with a numbered list. Maximum 5 steps. Format:
1. [instruction]
2. [instruction]
3. [instruction]'''
                    }
                  ]
                }
              ],
              'generationConfig': {
                'maxOutputTokens': 500,
                'temperature': 0.3,
              }
            }),
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => http.Response('{"error":"timeout"}', 408),
          );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text =
            data['candidates'][0]['content']['parts'][0]['text'] as String;
        return _parseSteps(text);
      } else {
        print('=== GEMINI ERROR [analyzeScreenAndGuide] ===');
        print('Status: ${response.statusCode}');
        print('Body: ${response.body}');
        return [
          'Error ${response.statusCode}. Check the terminal for details.'
        ];
      }
    } catch (e) {
      print('=== EXCEPTION: $e ===');
      if (e.toString().contains('SocketException') ||
          e.toString().contains('timeout')) {
        return [
          'No internet connection. Please check your WiFi and try again.'
        ];
      }
      return ['Unexpected error: ${e.toString()}'];
    }
  }

  // ── EXISTING: text-only quick help ───────────────────────────────────────

  Future<String> quickHelp(String question) async {
    try {
      final response = await http
          .post(
            Uri.parse(_apiUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {
                      'text':
                          'You are a technology assistant for elderly users. '
                              'Answer this question in very simple language, max 3 short sentences: '
                              '"$question"'
                    }
                  ]
                }
              ],
              'generationConfig': {'maxOutputTokens': 200, 'temperature': 0.3}
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['candidates'][0]['content']['parts'][0]['text'] as String;
      }
      return 'Could not get a response. Please try again.';
    } catch (e) {
      return 'No connection. Check your internet and try again.';
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

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

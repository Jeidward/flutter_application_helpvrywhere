import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

// ── Data classes ────────────────────────────────────────────────────────────

/// One guidance step returned by Gemini for the overlay loop.
///
/// Voice-first design: the instruction is the *only* signal the overlay
/// uses to guide the user. There is no spatial highlight — vision models
/// are unreliable at coordinates and the overlay would block the very tap
/// we're asking the user to make. Instead, the instruction is shown in a
/// small movable pill on screen and read aloud via TTS.
class AiStep {
  final String instruction; // What the user must do — read aloud by TTS
  final bool isComplete; // true = goal reached, close the overlay
  final int stepNumber;

  const AiStep({
    required this.instruction,
    required this.isComplete,
    this.stepNumber = 1,
  });

  factory AiStep.fromJson(Map<String, dynamic> json) {
    return AiStep(
      instruction:
          (json['instruction'] as String?)?.trim() ??
          'Follow the instructions on screen.',
      isComplete: json['is_complete'] as bool? ?? false,
      stepNumber: json['step_number'] as int? ?? 1,
    );
  }

  /// Fallback when JSON parsing fails — plain text only.
  factory AiStep.error(String message) {
    return AiStep(instruction: message, isComplete: false);
  }
}

// ── Service ─────────────────────────────────────────────────────────────────

class AiService {
  // TODO(security): rotate this and move to --dart-define before shipping.
  // The previous value was exposed in chat — generate a fresh one in
  // https://aistudio.google.com/app/apikey when you get a chance.
  static const String _apiKey = 'AIzaSyBRf-mrOmvzJW_l_AGIolWmwrgYql1uKU4';

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

    final prompt =
        '''
You are an AI assistant helping elderly users (65+) use their smartphone.

The user's goal is: "$userGoal"
This is step $currentStep of the guidance session.

Analyze the screenshot CAREFULLY. Respond with ONLY a raw JSON object —
no markdown, no code blocks, no preamble like "Here is the JSON".

Required format:
{
  "instruction": "...",
  "is_complete": false,
  "step_number": $currentStep
}

── Field rules ────────────────────────────────────────────────────────

"instruction"
  - ONE action the user must do next.
  - Describe the target by COLOR, SHAPE, and POSITION using everyday
    language. The user will use this description to find the element
    themselves — be vivid and specific.
    GOOD: "Tap the red square with a white play button, near the bottom
           right of the screen — it is labeled YouTube."
    GOOD: "Tap the green circle with a white phone, in the bottom row of
           icons. It says WhatsApp underneath."
    BAD:  "Tap the WhatsApp icon."        ← too brand-specific
    BAD:  "Tap the third icon."           ← position only, not visual
  - You MAY include the brand name ONLY as a hint at the end, not as the
    primary identifier (e.g. "...labeled YouTube" / "...called WhatsApp").
  - Mention WHERE on the screen ("near the bottom row", "at the top",
    "in the middle on the left") so the user knows where to look.
  - Maximum 30 words. Simple language for elderly users. No jargon.

"is_complete": true ONLY if the goal is already achieved in this
  screenshot. If true, set instruction to "You reached your goal! You
  can close the assistant."
''';

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {
              'inline_data': {'mime_type': 'image/jpeg', 'data': base64Image},
            },
            {'text': prompt},
          ],
        },
      ],
      'generationConfig': {
        // Bumped from 300 — JSON responses with `instruction` text + the
        // highlight object were occasionally truncated mid-string at 300,
        // which then failed to parse and surfaced as a generic
        // "AI gave a confusing answer" error.
        'maxOutputTokens': 600,
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

        print(
          '=== GEMINI transient error ${response.statusCode} '
          '(attempt ${attempt + 1}/3) — retrying ===',
        );
      } catch (e) {
        print('=== AI SERVICE EXCEPTION (attempt ${attempt + 1}/3): $e ===');
        if (e.toString().contains('SocketException')) {
          return AiStep.error(
            'No internet connection. Please check your WiFi and try again.',
          );
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
      return _parseGuidanceResponse(response.body);
    }

    print('=== GEMINI ERROR after retries [analyzeScreenForGuidance] ===');
    print('Status: ${response.statusCode}');
    print('Body: ${response.body}');

    // Surface a more useful hint when we know the cause.
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

  /// Defensive parser for Gemini's JSON-mode response.
  ///
  /// The previous version assumed the happy-path shape
  /// `candidates[0].content.parts[0].text` always exists. In reality Gemini
  /// can omit the parts array entirely when:
  ///   - `finishReason == "SAFETY"`        (safety filter blocked the answer)
  ///   - `finishReason == "MAX_TOKENS"`    (output was cut off mid-stream)
  ///   - `finishReason == "RECITATION"`    (model thought it was reciting)
  ///   - `promptFeedback.blockReason`      (prompt itself was blocked)
  /// In those cases the old code threw a `Null check operator used on a null
  /// value` and surfaced a generic "AI gave a confusing answer".
  AiStep _parseGuidanceResponse(String responseBody) {
    final dynamic data;
    try {
      data = jsonDecode(responseBody);
    } catch (e) {
      print('=== GEMINI: response was not JSON: $e ===');
      print(
        '=== Body (first 500 chars): '
        '${responseBody.substring(0, responseBody.length.clamp(0, 500))}',
      );
      return AiStep.error(
        'AI returned an unreadable response. Please try again.',
      );
    }

    // Prompt-level block? No candidates at all.
    final blockReason = data['promptFeedback']?['blockReason'];
    if (blockReason != null) {
      print('=== GEMINI: prompt blocked, reason=$blockReason ===');
      return AiStep.error(
        'The AI declined to analyze this screen. Try a different request.',
      );
    }

    final candidates = data['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      print('=== GEMINI: no candidates in response ===');
      print('Body: $responseBody');
      return AiStep.error('Could not analyze the screen. Please try again.');
    }

    final cand = candidates[0] as Map<String, dynamic>;
    final finishReason = cand['finishReason'] as String?;
    final parts = cand['content']?['parts'];

    if (parts is! List || parts.isEmpty) {
      print('=== GEMINI: empty parts (finishReason=$finishReason) ===');
      switch (finishReason) {
        case 'SAFETY':
          return AiStep.error(
            'The AI refused this screen for safety reasons. Try a different request.',
          );
        case 'MAX_TOKENS':
          return AiStep.error(
            'The AI ran out of room to answer. Try again — it usually works.',
          );
        case 'RECITATION':
          return AiStep.error(
            'The AI declined to repeat copyrighted content. Try rewording.',
          );
        default:
          return AiStep.error(
            'Could not analyze the screen. Please try again.',
          );
      }
    }

    final rawText = (parts[0] as Map<String, dynamic>)['text'] as String? ?? '';
    if (rawText.trim().isEmpty) {
      print('=== GEMINI: empty text part (finishReason=$finishReason) ===');
      return AiStep.error('AI returned no answer. Please try again.');
    }

    var cleaned = rawText
        .trim()
        .replaceAll('```json', '')
        .replaceAll('```', '')
        .trim();

    // Slice everything between the first `{` and the last `}` — handles the
    // occasional case where Gemini prepends preamble text before the JSON.
    final firstBrace = cleaned.indexOf('{');
    final lastBrace = cleaned.lastIndexOf('}');
    if (firstBrace >= 0 && lastBrace > firstBrace) {
      cleaned = cleaned.substring(firstBrace, lastBrace + 1);
    }

    try {
      final jsonMap = jsonDecode(cleaned) as Map<String, dynamic>;
      return AiStep.fromJson(jsonMap);
    } catch (e) {
      // If we hit MAX_TOKENS the JSON will be truncated mid-string. Tell the
      // user something useful instead of a generic confusion message.
      if (finishReason == 'MAX_TOKENS') {
        return AiStep.error('The AI answer was cut off. Please try again.');
      }
      print(
        '=== JSON parse failed (finishReason=$finishReason). '
        'Raw text: $rawText ===',
      );
      return AiStep.error('AI gave a confusing answer. Please try again.');
    }
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
                      },
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
3. [instruction]''',
                    },
                  ],
                },
              ],
              'generationConfig': {'maxOutputTokens': 500, 'temperature': 0.3},
            }),
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => http.Response('{"error":"timeout"}', 408),
          );

      if (response.statusCode == 200) {
        final text = _safeExtractText(response.body);
        if (text == null) {
          return ['Could not analyze the image. Please try again.'];
        }
        return _parseSteps(text);
      } else {
        print('=== GEMINI ERROR [analyzeScreenAndGuide] ===');
        print('Status: ${response.statusCode}');
        print('Body: ${response.body}');
        return [
          'Error ${response.statusCode}. Check the terminal for details.',
        ];
      }
    } catch (e) {
      print('=== EXCEPTION: $e ===');
      if (e.toString().contains('SocketException') ||
          e.toString().contains('timeout')) {
        return [
          'No internet connection. Please check your WiFi and try again.',
        ];
      }
      return ['Unexpected error: ${e.toString()}'];
    }
  }

  /// Best-effort extraction of the assistant text from Gemini's response.
  /// Returns null when there's no usable text (safety block, empty parts, …).
  String? _safeExtractText(String responseBody) {
    try {
      final data = jsonDecode(responseBody);
      if (data['promptFeedback']?['blockReason'] != null) return null;
      final candidates = data['candidates'];
      if (candidates is! List || candidates.isEmpty) return null;
      final parts = candidates[0]['content']?['parts'];
      if (parts is! List || parts.isEmpty) return null;
      final text = parts[0]['text'] as String?;
      if (text == null || text.trim().isEmpty) return null;
      return text;
    } catch (_) {
      return null;
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
                          '"$question"',
                    },
                  ],
                },
              ],
              'generationConfig': {'maxOutputTokens': 200, 'temperature': 0.3},
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final text = _safeExtractText(response.body);
        return text ?? 'Could not get a response. Please try again.';
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

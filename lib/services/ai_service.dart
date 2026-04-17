import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class AiService {
  static const String _apiKey = 'YOUR_GEMINI_API_KEY_HERE';
  static const String _model = 'gemini-2.5-flash';

  static String get _apiUrl =>
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent?key=$_apiKey';

  Future<List<String>> analyzeScreenAndGuide({
    required Uint8List imageBytes,
    required String userGoal,
  }) async {
    final base64Image = base64Encode(imageBytes);

    try {
      final response = await http.post(
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
                  'text': '''You are a technology assistant helping elderly users (65+) use their smartphones.

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
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () => http.Response('{"error":"timeout"}', 408),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text =
            data['candidates'][0]['content']['parts'][0]['text'] as String;
        return _parseSteps(text);
      } else {
        print('=== GEMINI ERROR ===');
        print('Status: ${response.statusCode}');
        print('Body: ${response.body}');
        print('====================');
        return ['Error ${response.statusCode}. Check the terminal for details.'];
      }
    } catch (e) {
      print('=== EXCEPTION: $e ===');
      if (e.toString().contains('SocketException') ||
          e.toString().contains('timeout')) {
        return ['No internet connection. Please check your WiFi and try again.'];
      }
      return ['Unexpected error: ${e.toString()}'];
    }
  }

  Future<String> quickHelp(String question) async {
    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {
                  'text': 'You are a technology assistant for elderly users. '
                      'Answer this question in very simple language, max 3 short sentences: '
                      '"$question"'
                }
              ]
            }
          ],
          'generationConfig': {'maxOutputTokens': 200, 'temperature': 0.3}
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['candidates'][0]['content']['parts'][0]['text'] as String;
      }
      return 'Could not get a response. Please try again.';
    } catch (e) {
      return 'No connection. Check your internet and try again.';
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

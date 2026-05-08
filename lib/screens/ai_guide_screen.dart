import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/ai_service.dart';

class AIGuideScreen extends StatefulWidget {
  const AIGuideScreen({super.key});

  @override
  State<AIGuideScreen> createState() => _AIGuideScreenState();
}

class _AIGuideScreenState extends State<AIGuideScreen> {
  final TextEditingController _goalController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  final AiService _aiService = AiService();

  Uint8List? _imageBytes;
  bool _isLoading = false;

  @override
  void dispose() {
    _goalController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final XFile? picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() => _imageBytes = bytes);
  }

  Future<void> _analyzeImage() async {
    if (_imageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an image first.')),
      );
      return;
    }
    if (_goalController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please describe what you need help with.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final steps = await _aiService.analyzeScreenAndGuide(
      imageBytes: _imageBytes!,
      userGoal: _goalController.text.trim(),
    );

    setState(() => _isLoading = false);

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StepsScreen(
            steps: steps,
            goal: _goalController.text.trim(),
          ),
        ),
      );
    }
  }

  void _reset() {
    setState(() {
      _imageBytes = null;
      _goalController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A6B5A),
        foregroundColor: Colors.white,
        title: const Text('AI Guide',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _reset,
              tooltip: 'Reset'),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Step 1 — What do you need help with?',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A3A2A))),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ],
              ),
              child: TextField(
                controller: _goalController,
                maxLines: 2,
                style: const TextStyle(fontSize: 16),
                decoration: const InputDecoration(
                  hintText: 'e.g. "I want to open WhatsApp"',
                  hintStyle: TextStyle(color: Color(0xFFAAAAAA)),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(16),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text('Step 2 — Select an image',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A3A2A))),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                width: double.infinity,
                height: 200,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: const Color(0xFF1A6B5A), width: 2),
                ),
                child: _imageBytes != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.memory(_imageBytes!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: 200),
                      )
                    : const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined,
                              size: 52, color: Color(0xFF1A6B5A)),
                          SizedBox(height: 8),
                          Text('Tap to select an image',
                              style: TextStyle(
                                  fontSize: 16,
                                  color: Color(0xFF1A6B5A),
                                  fontWeight: FontWeight.w500)),
                        ],
                      ),
              ),
            ),
            if (_imageBytes != null) ...[
              const SizedBox(height: 8),
              const Row(children: [
                Icon(Icons.check_circle, color: Color(0xFF1A6B5A), size: 18),
                SizedBox(width: 6),
                Text('Image selected',
                    style: TextStyle(
                        color: Color(0xFF1A6B5A),
                        fontWeight: FontWeight.w600)),
              ]),
            ],
            const SizedBox(height: 24),
            const Text('Step 3 — Get AI Analysis',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A3A2A))),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _analyzeImage,
                icon: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.auto_awesome),
                label: Text(_isLoading ? 'Analyzing...' : 'Analyze Image',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A6B5A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

// ── Results screen — all steps visible at once ───────────────────────
class StepsScreen extends StatelessWidget {
  final List<String> steps;
  final String goal;

  const StepsScreen({super.key, required this.steps, required this.goal});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A6B5A),
        foregroundColor: Colors.white,
        title: const Text('AI Analysis',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Goal reminder
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFE0F0EB),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.flag_outlined,
                      color: Color(0xFF1A6B5A), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Goal: "$goal"',
                      style: const TextStyle(
                          color: Color(0xFF1A3A2A),
                          fontSize: 14,
                          fontStyle: FontStyle.italic),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // All steps
            ...List.generate(steps.length, (i) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 2))
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Step number circle
                      Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(
                          color: Color(0xFF1A6B5A),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      // Step text
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            steps[i],
                            style: const TextStyle(
                                fontSize: 16,
                                color: Color(0xFF1A3A2A),
                                height: 1.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),

            const SizedBox(height: 24),

            // Back button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Analyze another image',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A6B5A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../services/request_service.dart';
import '../models/request_model.dart';

class RequestCreationScreen extends StatefulWidget {
  const RequestCreationScreen({super.key});

  @override
  State<RequestCreationScreen> createState() => _RequestCreationScreenState();
}

class _RequestCreationScreenState extends State<RequestCreationScreen> {
  final RequestService _service = RequestService();

  String? lastCreatedId;

  // CREATE
  Future<void> createRequest() async {
    final request = RequestModel(
      id: '',
      title: 'Test Request',
      category: 'Test',
      description: 'Created from button',
      location: 'Paris',
      dateTime: DateTime.now(),
      phone: '0000000000',
      status: RequestStatus.active,
      createdAt: DateTime.now(),
      userId: 'test_user',
    );

    final doc = await _service.createRequest(request);

    setState(() {
      lastCreatedId = doc.id;
    });

    print('Created ID: ${doc.id}');
  }

  // DELETE
  Future<void> deleteRequest() async {
    if (lastCreatedId == null) {
      print('No document to delete');
      return;
    }

    await _service.deleteRequest(lastCreatedId!);

    print('Deleted ID: $lastCreatedId');

    setState(() {
      lastCreatedId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Request Creation Test')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: createRequest,
              child: const Text('Create Request'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: deleteRequest,
              child: const Text('Delete Request'),
            ),
            const SizedBox(height: 20),
            Text(
              lastCreatedId != null
                  ? 'Last created ID: $lastCreatedId'
                  : 'No request created',
            ),
          ],
        ),
      ),
    );
  }
}

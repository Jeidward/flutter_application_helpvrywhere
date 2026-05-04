import 'package:flutter/material.dart';
import '../services/request_service.dart';
import '../models/request_model.dart';
import '../services/auth_service.dart';
import 'request_edit_screen.dart';

class RequestListScreen extends StatefulWidget {
  const RequestListScreen({super.key});

  @override
  State<RequestListScreen> createState() => _RequestListScreenState();
}

class _RequestListScreenState extends State<RequestListScreen> {
  final RequestService _service = RequestService();
  final AuthService _authService = AuthService();

  Color getCardColor(RequestStatus status) {
    switch (status) {
      case RequestStatus.cancelled:
        return Colors.red.shade100;
      case RequestStatus.completed:
        return Colors.green.shade100;
      default:
        return Colors.white;
    }
  }

  Widget _buildStat(String label, int value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value.toString(),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(label),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;

    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not logged in')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('My Requests')),
      body: StreamBuilder<List<RequestModel>>(
        stream: _service.getUserRequests(user.uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return const Center(child: Text('Error loading requests'));
          }

          final requests = snapshot.data ?? [];

          if (requests.isEmpty) {
            return const Center(child: Text('No requests found'));
          }

          // TRI
          requests.sort((a, b) {
            int getPriority(RequestStatus status) {
              switch (status) {
                case RequestStatus.active:
                  return 0;
                case RequestStatus.completed:
                  return 1;
                case RequestStatus.cancelled:
                  return 2;
              }
            }

            return getPriority(a.status).compareTo(getPriority(b.status));
          });

          final activeCount = requests
              .where((r) => r.status == RequestStatus.active)
              .length;
          final completedCount = requests
              .where((r) => r.status == RequestStatus.completed)
              .length;
          final cancelledCount = requests
              .where((r) => r.status == RequestStatus.cancelled)
              .length;

          return Column(
            children: [
              // Table
              Padding(
                padding: const EdgeInsets.all(12),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStat("Pending", activeCount, Colors.orange),
                        _buildStat("Done", completedCount, Colors.green),
                        _buildStat("Cancelled", cancelledCount, Colors.red),
                      ],
                    ),
                  ),
                ),
              ),

              // List
              Expanded(
                child: ListView.builder(
                  itemCount: requests.length,
                  itemBuilder: (context, index) {
                    final request = requests[index];

                    return Card(
                      color: getCardColor(request.status),
                      child: ListTile(
                        title: Text(
                          '${request.title} • ${request.status.name}',
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              request.category,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(request.description),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // EDIT
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        RequestEditScreen(request: request),
                                  ),
                                );
                              },
                            ),
                            // CANCEL
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _service.updateStatus(
                                  request.id,
                                  RequestStatus.cancelled,
                                );
                              },
                            ),
                            // COMPLETE
                            IconButton(
                              icon: const Icon(Icons.check),
                              onPressed: () {
                                _service.updateStatus(
                                  request.id,
                                  RequestStatus.completed,
                                );
                              },
                            ),
                            // DELETE
                            IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () {
                                _service.deleteRequest(request.id);
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/conversation_service.dart';
import '../services/user_service.dart';
import '../models/conversation_model.dart';
import 'chat_screen.dart';

class ConversationsScreen extends StatelessWidget {
  ConversationsScreen({super.key});

  final ConversationService _conversationService = ConversationService();
  final UserService _userService = UserService();

  Future<String> _getUserName(String uid) async {
    final name = await _userService.getUsername(uid);
    return name;
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return const Scaffold(
        body: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Messages",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              Center(child: Text("Not logged in")),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Messages",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 12),

            Expanded(
              child: StreamBuilder<List<ConversationModel>>(
                stream: _conversationService.getUserConversations(
                  currentUser.uid,
                ),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final conversations = snapshot.data!;

                  if (conversations.isEmpty) {
                    return const Center(child: Text("No conversations"));
                  }

                  return ListView.builder(
                    itemCount: conversations.length,
                    itemBuilder: (context, index) {
                      final conv = conversations[index];

                      final otherUserId = conv.users.firstWhere(
                        (id) => id != currentUser.uid,
                      );

                      return ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person)),

                        title: FutureBuilder<String>(
                          future: _getUserName(otherUserId),
                          builder: (context, snapshot) {
                            return Text(snapshot.data ?? "Loading...");
                          },
                        ),

                        subtitle: Text(conv.lastMessage),

                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                conversationId: conv.id,
                                otherUserId: otherUserId,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

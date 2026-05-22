import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/conversation_service.dart';
import '../models/conversation_model.dart';
import 'chat_screen.dart';

class ConversationsScreen extends StatelessWidget {
  ConversationsScreen({super.key});

  final ConversationService _conversationService = ConversationService();

  Future<void> _createTestConversation(String currentUserId) async {
    const otherUserId = "irDBc8fkhNUuowXp77uFJVduO6p2";

    await _conversationService.createConversation(
      currentUserId: currentUserId,
      otherUserId: otherUserId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return const Scaffold(body: Center(child: Text("Not logged in")));
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Messages")),

      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add_comment),
        onPressed: () async {
          await _createTestConversation(currentUser.uid);
        },
      ),

      body: StreamBuilder<List<ConversationModel>>(
        stream: _conversationService.getUserConversations(currentUser.uid),
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
                title: Text("User $otherUserId"),
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
    );
  }
}

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/message_model.dart';
import '../models/request_model.dart';
import '../services/conversation_service.dart';
import '../services/request_service.dart';
import '../services/user_service.dart';
import 'request_detail_screen.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String otherUserId;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.otherUserId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController controller = TextEditingController();
  final ConversationService _service = ConversationService();
  final RequestService _request = RequestService();
  final UserService _userService = UserService();
  final currentUser = FirebaseAuth.instance.currentUser!;

  String? username;

  @override
  void initState() {
    super.initState();
    _loadUsername();
  }

  Future<void> _loadUsername() async {
    final name = await _userService.getUsername(widget.otherUserId);

    if (!mounted) return;

    setState(() {
      username = name;
    });
  }

  void sendMessage() async {
    final text = controller.text.trim();

    if (text.isEmpty) return;

    await _service.sendMessage(
      conversationId: widget.conversationId,
      senderId: currentUser.uid,
      text: text,
    );

    controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser!;

    return Scaffold(
      appBar: AppBar(
        title: Text(username != null ? "Chat with $username" : "Chat"),
      ),

      body: Column(
        children: [
          StreamBuilder<List<RequestModel>>(
            stream: _request.getRequestsBetweenUsers(
              currentUser.uid,
              widget.otherUserId,
            ),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const SizedBox.shrink();
              }

              final requests = snapshot.data!;

              if (requests.isEmpty) {
                return const SizedBox.shrink();
              }

              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: requests.map((r) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        // Tappable chip — opens the full request detail
                        // screen. Conversion from RequestModel →
                        // NearbyRequest happens inside the static
                        // helper so this call site stays trivial.
                        child: Material(
                          color: Colors.blue[200],
                          borderRadius: BorderRadius.circular(20),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => RequestDetailScreen.openForModel(
                              context,
                              r,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Text(
                                r.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              );
            },
          ),
          Expanded(
            child: StreamBuilder<List<MessageModel>>(
              stream: _service.getMessages(widget.conversationId),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data!;

                return ListView.builder(
                  reverse: true,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];

                    final isMe = message.senderId == currentUser.uid;

                    return Align(
                      alignment: isMe
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.all(8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isMe ? Colors.blue : Colors.grey[300],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          message.text,
                          style: TextStyle(
                            color: isMe ? Colors.white : Colors.black,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    decoration: const InputDecoration(hintText: "Message..."),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

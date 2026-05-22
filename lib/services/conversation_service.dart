import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/conversation_model.dart';
import '../models/message_model.dart';

class ConversationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// COLLECTION REFERENCES
  CollectionReference<Map<String, dynamic>> get conversationsRef =>
      _firestore.collection('conversations');

  /// CONVERSATION ID
  String getConversationId(String uid1, String uid2) {
    final ids = [uid1, uid2]..sort();
    return ids.join('_');
  }

  /// CREATE CONVERSATION
  Future<String> createConversation({
    required String currentUserId,
    required String otherUserId,
  }) async {
    final conversationId = getConversationId(currentUserId, otherUserId);

    final conversationDoc = conversationsRef.doc(conversationId);

    final snapshot = await conversationDoc.get();

    /// Conversation already exists
    if (snapshot.exists) {
      return conversationId;
    }

    final conversation = ConversationModel(
      id: conversationId,
      users: [currentUserId, otherUserId],
      lastMessage: '',
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
    );

    await conversationDoc.set(conversation.toMap());

    return conversationId;
  }

  /// SEND MESSAGE
  Future<void> sendMessage({
    required String conversationId,
    required String senderId,
    required String text,
  }) async {
    final messageDoc = conversationsRef
        .doc(conversationId)
        .collection('messages')
        .doc();

    final message = MessageModel(
      id: messageDoc.id,
      senderId: senderId,
      text: text,
      createdAt: Timestamp.now(),
    );

    /// Add message
    await messageDoc.set(message.toMap());

    /// Update conversation
    await conversationsRef.doc(conversationId).update({
      'lastMessage': text,
      'updatedAt': Timestamp.now(),
    });
  }

  /// GET USER CONVERSATIONS
  Stream<List<ConversationModel>> getUserConversations(String userId) {
    return conversationsRef
        .where('users', arrayContains: userId)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            return ConversationModel.fromMap(doc.id, doc.data());
          }).toList();
        });
  }

  /// GET MESSAGES
  Stream<List<MessageModel>> getMessages(String conversationId) {
    return conversationsRef
        .doc(conversationId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            return MessageModel.fromMap(doc.id, doc.data());
          }).toList();
        });
  }
}

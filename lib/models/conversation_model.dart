import 'package:cloud_firestore/cloud_firestore.dart';

class ConversationModel {
  final String id;
  final List<String> users;
  final String lastMessage;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  ConversationModel({
    required this.id,
    required this.users,
    required this.lastMessage,
    this.createdAt,
    this.updatedAt,
  });

  factory ConversationModel.fromMap(String id, Map<String, dynamic> data) {
    return ConversationModel(
      id: id,
      users: List<String>.from(data['users'] ?? []),
      lastMessage: data['lastMessage'] ?? '',
      createdAt: data['createdAt'],
      updatedAt: data['updatedAt'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'users': users,
      'lastMessage': lastMessage,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;           // Firebase Auth unique user ID
  final String email;         // Used for login and contact
  final String username;      // Unique name chosen by user — shown on HomeScreen greeting and profile
  final String? photoUrl;     // Profile picture — auto-filled by Google sign-in, null for email users
  final bool isPhoneVerified; // Phone-verified users can access help request features
  final DateTime createdAt;   // Timestamp when the user account was created

  UserModel({
    required this.uid,
    required this.email,
    required this.username,
    this.photoUrl,
    required this.isPhoneVerified,
    required this.createdAt,
  });

  /// Creates a UserModel from a Firestore document snapshot
  factory UserModel.fromMap(Map<String, dynamic> data, String uid) {
    return UserModel(
      uid: uid,
      email: data['email'] ?? '',
      username: data['username'] ?? '',
      photoUrl: data['photoUrl'],
      isPhoneVerified: data['isPhoneVerified'] ?? false,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
    );
  }

  /// Converts UserModel to a Map for saving to Firestore
  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'username': username,
      'photoUrl': photoUrl,
      'isPhoneVerified': isPhoneVerified,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}

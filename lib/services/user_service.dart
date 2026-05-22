import 'package:cloud_firestore/cloud_firestore.dart';

class UserService {
  final _usersRef = FirebaseFirestore.instance.collection('users');

  Future<String> getUsername(String uid) async {
    final doc = await _usersRef.doc(uid).get();

    if (!doc.exists) return "Unknown";

    return doc.data()?['username'] ?? "Unknown";
  }
}

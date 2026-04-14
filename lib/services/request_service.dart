import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/request_model.dart';

class RequestService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  final String collection = 'requests';

  // CREATE
  Future<DocumentReference> createRequest(RequestModel request) async {
    return await _db.collection(collection).add(request.toMap());
  }

  // READ
  Stream<List<RequestModel>> getRequests() {
    return _db
        .collection(collection)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => RequestModel.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  // READ EVERY REQUEST FOR ONE USER
  Stream<List<RequestModel>> getUserRequests(String userId) {
    return _db
        .collection(collection)
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => RequestModel.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  // UPDATE
  Future<void> updateRequest(String id, Map<String, dynamic> data) async {
    await _db.collection(collection).doc(id).update(data);
  }

  // UPDATE STATUS
  Future<void> updateStatus(String id, RequestStatus status) async {
    await _db.collection(collection).doc(id).update({'status': status.name});
  }

  // DELETE
  Future<void> deleteRequest(String id) async {
    await _db.collection(collection).doc(id).delete();
  }
}

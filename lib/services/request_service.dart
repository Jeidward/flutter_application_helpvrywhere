import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/request_model.dart';
import '../services/conversation_service.dart';

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

  // GET A REQUEST BY ITS ID
  Future<RequestModel?> getRequestById(String id) async {
    final doc = await _db.collection(collection).doc(id).get();

    if (!doc.exists) return null;

    return RequestModel.fromMap(doc.data()!, doc.id);
  }

  /// Atomically claim a request for the given volunteer. Uses a Firestore
  /// transaction so two volunteers tapping "I can help" at the same time
  /// can't both succeed — the second one gets [AcceptResult.alreadyTaken].
  ///
  /// Returns:
  ///   • [AcceptResult.success]      → you got it, request is now `accepted`
  ///   • [AcceptResult.alreadyTaken] → another volunteer beat you to it
  ///   • [AcceptResult.notActive]    → request was completed / cancelled
  ///   • [AcceptResult.notFound]     → doc no longer exists
  Future<AcceptResult> acceptRequest({
    required String requestId,
    required String helperUid,
  }) async {
    final docRef = _db.collection(collection).doc(requestId);
    return await _db.runTransaction<AcceptResult>((tx) async {
      final snapshot = await tx.get(docRef);
      if (!snapshot.exists) return AcceptResult.notFound;
      final data = snapshot.data()!;
      final existingHelper = data['helperUserId'] as String?;
      final status = data['status'] as String? ?? 'active';

      if (existingHelper != null && existingHelper.isNotEmpty) {
        return AcceptResult.alreadyTaken;
      }
      if (status != 'active') {
        return AcceptResult.notActive;
      }

      tx.update(docRef, {
        'helperUserId': helperUid,
        'acceptedAt': FieldValue.serverTimestamp(),
        'status': RequestStatus.accepted.name,
      });

      final ConversationService conversationService = ConversationService();
      await conversationService.createConversation(
        currentUserId: data['userId'],
        otherUserId: helperUid,
      );

      return AcceptResult.success;
    });
  }

  // DELETE
  Future<void> deleteRequest(String id) async {
    await _db.collection(collection).doc(id).delete();
  }

  Stream<List<RequestModel>> getRequestsBetweenUsers(
    String userA,
    String userB,
  ) {
    return getRequests().map((requests) {
      return requests.where((r) {
        return ((r.userId == userA && r.helperUserId == userB) ||
            (r.userId == userB && r.helperUserId == userA));
      }).toList();
    });
  }
}

/// Outcome of `RequestService.acceptRequest`. Lets the UI render a
/// helpful message when the accept fails for a known reason.
enum AcceptResult { success, alreadyTaken, notActive, notFound }

import 'package:cloud_firestore/cloud_firestore.dart';

/// Lifecycle of a help request.
///   active    – created, waiting for a volunteer
///   accepted  – a volunteer claimed it (their uid is in [RequestModel.helperUserId]).
///               No one else can claim it now.
///   completed – help was delivered
///   cancelled – requester pulled it
enum RequestStatus { active, accepted, completed, cancelled }

class RequestModel {
  final String id;
  final String title;
  final String category;
  final String description;
  final String? location;
  final double longitude;
  final double latitude;
  final DateTime dateTime;
  final String phone;
  final RequestStatus status;
  final DateTime createdAt;
  final String userId;

  /// The volunteer who accepted the request, or null while still open.
  /// Set atomically by `RequestService.acceptRequest()`.
  final String? helperUserId;

  /// When the volunteer accepted, or null while still open.
  final DateTime? acceptedAt;

  RequestModel({
    required this.id,
    required this.title,
    required this.category,
    required this.description,
    this.location,
    required this.latitude,
    required this.longitude,
    required this.dateTime,
    required this.phone,
    required this.status,
    required this.createdAt,
    required this.userId,
    this.helperUserId,
    this.acceptedAt,
  });

  factory RequestModel.fromMap(Map<String, dynamic> data, String id) {
    return RequestModel(
      id: id,
      title: data['title'] ?? '',
      category: data['category'] ?? '',
      description: data['description'] ?? '',
      location: data['location'] ?? '',
      longitude: (data['longitude'] ?? 0).toDouble(),
      latitude: (data['latitude'] ?? 0).toDouble(),
      dateTime: (data['dateTime'] as Timestamp).toDate(),
      phone: data['phone'] ?? '',
      status: _statusFromString(data['status']),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      userId: data['userId'] ?? '',
      helperUserId: data['helperUserId'] as String?,
      acceptedAt: data['acceptedAt'] != null
          ? (data['acceptedAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'category': category,
      'description': description,
      'location': location,
      'longitude': longitude,
      'latitude': latitude,
      'dateTime': Timestamp.fromDate(dateTime),
      'phone': phone,
      'status': status.name,
      'createdAt': FieldValue.serverTimestamp(),
      'userId': userId,
      'helperUserId': helperUserId,
      'acceptedAt': acceptedAt != null ? Timestamp.fromDate(acceptedAt!) : null,
    };
  }

  static RequestStatus _statusFromString(String? status) {
    switch (status) {
      case 'accepted':
        return RequestStatus.accepted;
      case 'completed':
        return RequestStatus.completed;
      case 'cancelled':
        return RequestStatus.cancelled;
      default:
        return RequestStatus.active;
    }
  }
}

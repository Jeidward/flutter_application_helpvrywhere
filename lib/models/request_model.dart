import 'package:cloud_firestore/cloud_firestore.dart';

enum RequestStatus { active, completed, cancelled }

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
    };
  }

  static RequestStatus _statusFromString(String? status) {
    switch (status) {
      case 'completed':
        return RequestStatus.completed;
      case 'cancelled':
        return RequestStatus.cancelled;
      default:
        return RequestStatus.active;
    }
  }
}

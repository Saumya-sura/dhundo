import 'package:cloud_firestore/cloud_firestore.dart';

class ItemModel {
  final String id;
  final String title;
  final String description;
  final String? imageUrl;
  final double latitude;
  final double longitude;
  final String locationDescription;
  final bool isLost;
  final String category;
  final DateTime dateTime;
  final String reporterId;
  final String reporterName;
  final String status; // 'active' or 'resolved'
  final String? verificationQuestion;
  final bool isAmberAlert;

  ItemModel({
    required this.id,
    required this.title,
    required this.description,
    this.imageUrl,
    required this.latitude,
    required this.longitude,
    required this.locationDescription,
    required this.isLost,
    required this.category,
    required this.dateTime,
    required this.reporterId,
    required this.reporterName,
    this.status = 'active',
    this.verificationQuestion,
    this.isAmberAlert = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'imageUrl': imageUrl,
      'latitude': latitude,
      'longitude': longitude,
      'locationDescription': locationDescription,
      'isLost': isLost,
      'category': category,
      'dateTime': Timestamp.fromDate(dateTime),
      'reporterId': reporterId,
      'reporterName': reporterName,
      'status': status,
      'verificationQuestion': verificationQuestion,
      'isAmberAlert': isAmberAlert,
    };
  }

  factory ItemModel.fromMap(Map<String, dynamic> map, String documentId) {
    DateTime parsedDate;
    if (map['dateTime'] is Timestamp) {
      parsedDate = (map['dateTime'] as Timestamp).toDate();
    } else if (map['dateTime'] is String) {
      parsedDate = DateTime.parse(map['dateTime']);
    } else {
      parsedDate = DateTime.now();
    }

    return ItemModel(
      id: documentId,
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      imageUrl: map['imageUrl'],
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0.0,
      locationDescription: map['locationDescription'] ?? '',
      isLost: map['isLost'] ?? true,
      category: map['category'] ?? 'General',
      dateTime: parsedDate,
      reporterId: map['reporterId'] ?? '',
      reporterName: map['reporterName'] ?? 'Anonymous',
      status: map['status'] ?? 'active',
      verificationQuestion: map['verificationQuestion'],
      isAmberAlert: map['isAmberAlert'] ?? false,
    );
  }

  ItemModel copyWith({
    String? id,
    String? title,
    String? description,
    String? imageUrl,
    double? latitude,
    double? longitude,
    String? locationDescription,
    bool? isLost,
    String? category,
    DateTime? dateTime,
    String? reporterId,
    String? reporterName,
    String? status,
    String? verificationQuestion,
    bool? isAmberAlert,
  }) {
    return ItemModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      locationDescription: locationDescription ?? this.locationDescription,
      isLost: isLost ?? this.isLost,
      category: category ?? this.category,
      dateTime: dateTime ?? this.dateTime,
      reporterId: reporterId ?? this.reporterId,
      reporterName: reporterName ?? this.reporterName,
      status: status ?? this.status,
      verificationQuestion: verificationQuestion ?? this.verificationQuestion,
      isAmberAlert: isAmberAlert ?? this.isAmberAlert,
    );
  }
}

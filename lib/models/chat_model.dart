import 'package:cloud_firestore/cloud_firestore.dart';

class ChatRoomModel {
  final String id;
  final String itemId;
  final String itemTitle;
  final bool itemIsLost;
  final String ownerId;
  final String ownerName;
  final String finderId;
  final String finderName;
  final String lastMessage;
  final DateTime lastMessageTime;
  final List<String> userIds;
  final String? callStatus; // 'ringing', 'connected', 'ended', or null
  final String? callerId;
  final String? callerName;
  final String? lastSenderId;
  final List<String> unreadBy;
  final Map<String, dynamic>? unreadCounts; // { uid: int count }
  final Map<String, dynamic>?
  liveLocations; // { uid: { 'latitude': double, 'longitude': double, 'updatedAt': Timestamp } }
  ChatRoomModel({
    required this.id,
    required this.itemId,
    required this.itemTitle,
    required this.itemIsLost,
    required this.ownerId,
    required this.ownerName,
    required this.finderId,
    required this.finderName,
    required this.lastMessage,
    required this.lastMessageTime,
    required this.userIds,
    this.callStatus,
    this.callerId,
    this.callerName,
    this.lastSenderId,
    this.unreadBy = const [],
    this.unreadCounts,
    this.liveLocations,
  });

  int getUnreadCount(String? currentUserId) {
    if (currentUserId == null) return 0;
    if (unreadCounts != null && unreadCounts![currentUserId] != null) {
      final val = unreadCounts![currentUserId];
      if (val is num) return val.toInt();
    }
    if (unreadBy.contains(currentUserId)) return 1;
    return 0;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'itemId': itemId,
      'itemTitle': itemTitle,
      'itemIsLost': itemIsLost,
      'ownerId': ownerId,
      'ownerName': ownerName,
      'finderId': finderId,
      'finderName': finderName,
      'lastMessage': lastMessage,
      'lastMessageTime': Timestamp.fromDate(lastMessageTime),
      'userIds': userIds,
      'callStatus': callStatus,
      'callerId': callerId,
      'callerName': callerName,
      'lastSenderId': lastSenderId,
      'unreadBy': unreadBy,
      'unreadCounts': unreadCounts,
      'liveLocations': liveLocations,
    };
  }

  factory ChatRoomModel.fromMap(Map<String, dynamic> map, String docId) {
    DateTime parsedTime;
    if (map['lastMessageTime'] is Timestamp) {
      parsedTime = (map['lastMessageTime'] as Timestamp).toDate();
    } else if (map['lastMessageTime'] is String) {
      parsedTime = DateTime.parse(map['lastMessageTime']);
    } else {
      parsedTime = DateTime.now();
    }

    return ChatRoomModel(
      id: docId,
      itemId: map['itemId'] ?? '',
      itemTitle: map['itemTitle'] ?? '',
      itemIsLost: map['itemIsLost'] ?? true,
      ownerId: map['ownerId'] ?? '',
      ownerName: map['ownerName'] ?? '',
      finderId: map['finderId'] ?? '',
      finderName: map['finderName'] ?? '',
      lastMessage: map['lastMessage'] ?? '',
      lastMessageTime: parsedTime,
      userIds: List<String>.from(map['userIds'] ?? []),
      callStatus: map['callStatus'],
      callerId: map['callerId'],
      callerName: map['callerName'],
      lastSenderId: map['lastSenderId'],
      unreadBy: List<String>.from(map['unreadBy'] ?? []),
      unreadCounts: map['unreadCounts'] != null
          ? Map<String, dynamic>.from(map['unreadCounts'])
          : null,
      liveLocations: map['liveLocations'] != null
          ? Map<String, dynamic>.from(map['liveLocations'])
          : null,
    );
  }
}

class MessageModel {
  final String id;
  final String senderId;
  final String senderName;
  final String text;
  final DateTime timestamp;
  final double? latitude;
  final double? longitude;
  final String? locationName;

  MessageModel({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.timestamp,
    this.latitude,
    this.longitude,
    this.locationName,
  });

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'senderName': senderName,
      'text': text,
      'timestamp': Timestamp.fromDate(timestamp),
      'latitude': latitude,
      'longitude': longitude,
      'locationName': locationName,
    };
  }

  factory MessageModel.fromMap(Map<String, dynamic> map, String docId) {
    DateTime parsedTime;
    if (map['timestamp'] is Timestamp) {
      parsedTime = (map['timestamp'] as Timestamp).toDate();
    } else if (map['timestamp'] is String) {
      parsedTime = DateTime.parse(map['timestamp']);
    } else {
      parsedTime = DateTime.now();
    }

    return MessageModel(
      id: docId,
      senderId: map['senderId'] ?? '',
      senderName: map['senderName'] ?? '',
      text: map['text'] ?? '',
      timestamp: parsedTime,
      latitude: map['latitude'] != null
          ? (map['latitude'] as num).toDouble()
          : null,
      longitude: map['longitude'] != null
          ? (map['longitude'] as num).toDouble()
          : null,
      locationName: map['locationName'],
    );
  }
}

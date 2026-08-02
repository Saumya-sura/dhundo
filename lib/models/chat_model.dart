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
  });

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
    );
  }
}

class MessageModel {
  final String id;
  final String senderId;
  final String senderName;
  final String text;
  final DateTime timestamp;

  MessageModel({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'senderName': senderName,
      'text': text,
      'timestamp': Timestamp.fromDate(timestamp),
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
    );
  }
}

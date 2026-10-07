import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/item_model.dart';
import '../models/chat_model.dart';

class FirebaseService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  FirebaseService() {
    _enableOfflinePersistence();
  }

  void _enableOfflinePersistence() {
    try {
      _db.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
    } catch (_) {}
  }

  User? get currentUser => _auth.currentUser;
  String? get currentUserId => _auth.currentUser?.uid;
  String? get currentUserEmail => _auth.currentUser?.email;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // -----------------------------------------
  // AUTH SERVICES
  // -----------------------------------------

  Future<UserCredential> signIn(String email, String password) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      notifyListeners();
      return cred;
    } catch (e) {
      rethrow;
    }
  }

  Future<UserCredential> signUp(String email, String password, String name) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      // Update display name
      await cred.user?.updateDisplayName(name);
      
      // Store user details in database
      await _db.collection('users').doc(cred.user!.uid).set({
        'uid': cred.user!.uid,
        'email': email,
        'name': name,
        'createdAt': FieldValue.serverTimestamp(),
      });

      notifyListeners();
      return cred;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    notifyListeners();
  }

  Future<String> getUserName(String userId) async {
    try {
      final doc = await _db.collection('users').doc(userId).get();
      if (doc.exists) {
        return doc.data()?['name'] ?? 'User';
      }
    } catch (_) {}
    return 'User';
  }

  // -----------------------------------------
  // IMAGES UPLOAD
  // -----------------------------------------

  Future<String?> uploadImage(String itemId, dynamic imageSource) async {
    try {
      final ref = _storage.ref().child('item_images').child('$itemId.jpg');
      
      if (kIsWeb) {
        if (imageSource is Uint8List) {
          final uploadTask = await ref.putData(imageSource);
          return await uploadTask.ref.getDownloadURL();
        }
      } else {
        if (imageSource is File) {
          final uploadTask = await ref.putFile(imageSource);
          return await uploadTask.ref.getDownloadURL();
        } else if (imageSource is String) {
          // It's a file path
          final uploadTask = await ref.putFile(File(imageSource));
          return await uploadTask.ref.getDownloadURL();
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error uploading image: $e');
      }
    }
    return null;
  }

  // -----------------------------------------
  // LOST/FOUND ITEMS
  // -----------------------------------------

  Future<void> reportItem(ItemModel item, {dynamic imageSource}) async {
    try {
      String? imageUrl = item.imageUrl;
      if (imageSource != null) {
        imageUrl = await uploadImage(item.id, imageSource);
      }

      final itemWithImage = item.copyWith(imageUrl: imageUrl);
      
      await _db.collection('items').doc(item.id).set(itemWithImage.toMap());
    } catch (e) {
      rethrow;
    }
  }

  Future<void> resolveItem(String itemId) async {
    try {
      await _db.collection('items').doc(itemId).update({'status': 'resolved'});
    } catch (e) {
      rethrow;
    }
  }

  Stream<List<ItemModel>> getItems() {
    return _db
        .collection('items')
        .orderBy('dateTime', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => ItemModel.fromMap(doc.data(), doc.id))
          .toList();
    });
  }

  // Distance helper using Haversine formula
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double r = 6371; // Earth radius in kilometers
    final double dLat = _degToRad(lat2 - lat1);
    final double dLon = _degToRad(lon2 - lon1);
    
    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(lat1)) * cos(_degToRad(lat2)) *
        sin(dLon / 2) * sin(dLon / 2);
    
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c; // Distance in kilometers
  }

  double _degToRad(double deg) {
    return deg * (pi / 180);
  }

  // Automated Match Engine: Client-Side proximity evaluation
  Future<List<ItemModel>> checkPotentialMatches(ItemModel newItem) async {
    try {
      // Find items in the same category (no composite index needed)
      final query = await _db
          .collection('items')
          .where('category', isEqualTo: newItem.category)
          .get();

      final List<ItemModel> matches = [];

      for (var doc in query.docs) {
        final candidate = ItemModel.fromMap(doc.data(), doc.id);
        
        // Exclude own items
        if (candidate.reporterId == newItem.reporterId) continue;
        
        // Match opposite types (lost vs found)
        if (candidate.isLost == newItem.isLost) continue;
        
        // Match active items only
        if (candidate.status != 'active') continue;
        
        // Calculate distance
        final distance = _calculateDistance(
          newItem.latitude,
          newItem.longitude,
          candidate.latitude,
          candidate.longitude,
        );

        // Distance threshold: 10 km
        if (distance <= 10.0) {
          matches.add(candidate);
        }
      }

      return matches;
    } catch (e) {
      if (kDebugMode) {
        print('Error checking potential matches: $e');
      }
      return [];
    }
  }

  // -----------------------------------------
  // CHAT SERVICES
  // -----------------------------------------

  Future<ChatRoomModel> getOrCreateChatRoom({
    required String itemId,
    required String itemTitle,
    required bool itemIsLost,
    required String ownerId,
    required String ownerName,
    required String finderId,
    required String finderName,
  }) async {
    // Generate a consistent ID based on user IDs and item ID to prevent duplicate chat rooms
    // We sort users ID list to ensure the ID is always identical regardless of who opens the chat
    final List<String> sortedUsers = [ownerId, finderId]..sort();
    final String chatRoomId = '${itemId}_${sortedUsers[0]}_${sortedUsers[1]}';

    try {
      final doc = await _db.collection('chats').doc(chatRoomId).get();
      
      if (doc.exists) {
        return ChatRoomModel.fromMap(doc.data()!, doc.id);
      } else {
        final chatRoom = ChatRoomModel(
          id: chatRoomId,
          itemId: itemId,
          itemTitle: itemTitle,
          itemIsLost: itemIsLost,
          ownerId: ownerId,
          ownerName: ownerName,
          finderId: finderId,
          finderName: finderName,
          lastMessage: 'Chat initialized.',
          lastMessageTime: DateTime.now(),
          userIds: [ownerId, finderId],
        );

        await _db.collection('chats').doc(chatRoomId).set(chatRoom.toMap());
        return chatRoom;
      }
    } catch (e) {
      rethrow;
    }
  }

  Stream<List<ChatRoomModel>> getUserChatRooms() {
    final uid = currentUserId;
    if (uid == null) return Stream.value([]);

    return _db
        .collection('chats')
        .where('userIds', arrayContains: uid)
        .snapshots()
        .map((snapshot) {
      final rooms = snapshot.docs
          .map((doc) => ChatRoomModel.fromMap(doc.data(), doc.id))
          .toList();
      // Sort in-memory by lastMessageTime descending
      rooms.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
      return rooms;
    });
  }

  Stream<List<MessageModel>> getChatMessages(String chatRoomId) {
    return _db
        .collection('chats')
        .doc(chatRoomId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => MessageModel.fromMap(doc.data(), doc.id))
          .toList();
    });
  }

  Future<void> sendMessage(
    String chatRoomId,
    String text,
    String senderName, {
    double? latitude,
    double? longitude,
    String? locationName,
  }) async {
    final uid = currentUserId;
    if (uid == null) return;

    final batch = _db.batch();

    final messageRef = _db
        .collection('chats')
        .doc(chatRoomId)
        .collection('messages')
        .doc();

    final message = MessageModel(
      id: messageRef.id,
      senderId: uid,
      senderName: senderName,
      text: text,
      timestamp: DateTime.now(),
      latitude: latitude,
      longitude: longitude,
      locationName: locationName,
    );

    batch.set(messageRef, message.toMap());
    
    // Update chat room details
    final roomRef = _db.collection('chats').doc(chatRoomId);
    batch.update(roomRef, {
      'lastMessage': latitude != null ? '📍 Location: ${locationName ?? "Shared Place"}' : text,
      'lastMessageTime': Timestamp.fromDate(DateTime.now()),
    });

    await batch.commit();
  }

  // -----------------------------------------
  // USER PROFILES, RATINGS & TRUST SYSTEM
  // -----------------------------------------

  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      final doc = await _db.collection('users').doc(userId).get();
      return doc.data();
    } catch (_) {
      return null;
    }
  }

  Future<void> rateUser(String ratedUserId, double rating, List<String> tags) async {
    try {
      final docRef = _db.collection('users').doc(ratedUserId);
      final doc = await docRef.get();
      
      int ratingCount = 0;
      double ratingSum = 0.0;
      int karmaPoints = 0;
      List<String> badges = [];

      if (doc.exists) {
        final data = doc.data()!;
        ratingCount = data['ratingCount'] ?? 0;
        ratingSum = (data['ratingSum'] as num?)?.toDouble() ?? 0.0;
        karmaPoints = data['karmaPoints'] ?? 0;
        badges = List<String>.from(data['badges'] ?? []);
      }

      ratingCount += 1;
      ratingSum += rating;
      karmaPoints += 15; // Earn karma for resolving returns

      // Badge Rules
      if (karmaPoints >= 30 && !badges.contains('Super Finder')) {
        badges.add('Super Finder');
      }
      final double averageRating = ratingSum / ratingCount;
      if (averageRating >= 4.5 && ratingCount >= 3 && !badges.contains('Trusted Samaritan')) {
        badges.add('Trusted Samaritan');
      }
      if (!badges.contains('Good Citizen')) {
        badges.add('Good Citizen');
      }

      await docRef.set({
        'ratingCount': ratingCount,
        'ratingSum': ratingSum,
        'karmaPoints': karmaPoints,
        'badges': badges,
      }, SetOptions(merge: true));
    } catch (e) {
      if (kDebugMode) {
        print('Error rating user: $e');
      }
      rethrow;
    }
  }

  // -----------------------------------------
  // LIVE LOCATION SHARING
  // -----------------------------------------

  Future<void> updateLiveLocation(String chatRoomId, double latitude, double longitude) async {
    final uid = currentUserId;
    if (uid == null) return;
    await _db.collection('chats').doc(chatRoomId).update({
      'liveLocations.$uid': {
        'latitude': latitude,
        'longitude': longitude,
        'updatedAt': Timestamp.now(),
      }
    });
  }

  Future<void> stopSharingLocation(String chatRoomId) async {
    final uid = currentUserId;
    if (uid == null) return;
    await _db.collection('chats').doc(chatRoomId).update({
      'liveLocations.$uid': FieldValue.delete(),
    });
  }

  // -----------------------------------------
  // SIMULATED VOIP CALLING
  // -----------------------------------------

  Future<void> initiateCall(String chatRoomId, String callerName) async {
    final uid = currentUserId;
    if (uid == null) return;
    await _db.collection('chats').doc(chatRoomId).update({
      'callStatus': 'ringing',
      'callerId': uid,
      'callerName': callerName,
    });
  }

  Future<void> acceptCall(String chatRoomId) async {
    await _db.collection('chats').doc(chatRoomId).update({
      'callStatus': 'connected',
    });
  }

  Future<void> endCall(String chatRoomId) async {
    await _db.collection('chats').doc(chatRoomId).update({
      'callStatus': 'ended',
    });
  }

  Future<void> resetCallStatus(String chatRoomId) async {
    await _db.collection('chats').doc(chatRoomId).update({
      'callStatus': FieldValue.delete(),
      'callerId': FieldValue.delete(),
      'callerName': FieldValue.delete(),
    });
  }
}

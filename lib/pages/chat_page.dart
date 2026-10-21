import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import '../models/chat_model.dart';
import '../services/firebase_service.dart';
import '../services/google_maps_service.dart';
import '../theme/app_theme.dart';
import 'call_overlay_page.dart';
import '../widgets/rating_dialog.dart';
import '../widgets/glass_card.dart';
import '../widgets/street_view_dialog.dart';
import '../services/safe_places_service.dart';
import 'location_picker_page.dart';
import 'location_navigation_page.dart';

class ChatPage extends StatefulWidget {
  final ChatRoomModel chatRoom;

  const ChatPage({super.key, required this.chatRoom});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  GoogleMapController? _chatMapController;

  StreamSubscription? _incomingCallSubscription;
  StreamSubscription? _locationStreamSubscription;
  bool _isCallScreenOpen = false;
  bool _isSharingLocation = false;

  @override
  void initState() {
    super.initState();
    final firebaseService = Provider.of<FirebaseService>(
      context,
      listen: false,
    );
    firebaseService.markChatRoomAsRead(widget.chatRoom.id);

    // Listen to call signaling
    _incomingCallSubscription = firebaseService.getUserChatRooms().listen((
      rooms,
    ) {
      final room = rooms.where((r) => r.id == widget.chatRoom.id).firstOrNull;
      if (room != null &&
          room.callStatus == 'ringing' &&
          room.callerId != firebaseService.currentUserId) {
        if (!_isCallScreenOpen && mounted) {
          _isCallScreenOpen = true;
          final callerName = room.callerId == room.ownerId
              ? room.ownerName
              : room.finderName;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CallOverlayPage(
                chatRoomId: widget.chatRoom.id,
                otherPartyName: callerName,
                isCaller: false,
              ),
            ),
          ).then((_) {
            _isCallScreenOpen = false;
          });
        }
      }
    });
  }

  void _toggleLocationSharing(FirebaseService firebaseService) async {
    if (_isSharingLocation) {
      _locationStreamSubscription?.cancel();
      await firebaseService.stopSharingLocation(widget.chatRoom.id);
      setState(() {
        _isSharingLocation = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Stopped sharing location.')),
        );
      }
    } else {
      bool serviceEnabled;
      LocationPermission permission;

      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enable location services.')),
        );
        return;
      }

      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      setState(() {
        _isSharingLocation = true;
      });

      _locationStreamSubscription =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 5,
            ),
          ).listen((Position position) {
            firebaseService.updateLiveLocation(
              widget.chatRoom.id,
              position.latitude,
              position.longitude,
            );
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sharing live location in chat...')),
        );
      }
    }
  }

  Timer? _autoReplyTimer;

  @override
  void dispose() {
    _autoReplyTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _incomingCallSubscription?.cancel();
    _locationStreamSubscription?.cancel();
    if (_isSharingLocation) {
      final firebaseService = Provider.of<FirebaseService>(
        context,
        listen: false,
      );
      firebaseService.stopSharingLocation(widget.chatRoom.id);
    }
    super.dispose();
  }

  void _scheduleAutoReply(FirebaseService firebaseService) {
    _autoReplyTimer?.cancel();
    _autoReplyTimer = Timer(const Duration(seconds: 60), () async {
      if (!mounted) return;
      final currentUserId = firebaseService.currentUserId ?? '';
      final isOwner = widget.chatRoom.ownerId == currentUserId;
      final otherPartyId = isOwner
          ? widget.chatRoom.finderId
          : widget.chatRoom.ownerId;
      final otherPartyName = isOwner
          ? widget.chatRoom.finderName
          : widget.chatRoom.ownerName;

      final autoReplyText =
          "Hey! I'm currently busy right now, but I saw your message and will read it in a little while. Don't worry at all, your ${widget.chatRoom.itemTitle} will be safely returned and we'll arrange the handover! 🤝";

      try {
        await firebaseService.sendMessage(
          widget.chatRoom.id,
          autoReplyText,
          otherPartyName.isNotEmpty ? otherPartyName : 'Other Party',
          senderId: otherPartyId,
        );
      } catch (e) {
        debugPrint('Auto-reply error: $e');
      }
    });
  }

  void _send(FirebaseService firebaseService) async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();

    try {
      final name = firebaseService.currentUser?.displayName ?? 'Anonymous';
      await firebaseService.sendMessage(widget.chatRoom.id, text, name);
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
      _scheduleAutoReply(firebaseService);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send message: $e'),
            backgroundColor: AppTheme.lostColor,
          ),
        );
      }
    }
  }

  void _resolveItem(FirebaseService firebaseService) async {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.cardBg,
        title: const Text('Mark as Resolved'),
        content: const Text(
          'Confirming that the item has been returned? This will archive the map pin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                await firebaseService.resolveItem(widget.chatRoom.itemId);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Item marked as resolved/returned!'),
                      backgroundColor: AppTheme.foundColor,
                    ),
                  );

                  // Trigger user rating flow
                  final currentUserId = firebaseService.currentUserId ?? '';
                  final isOwner = widget.chatRoom.ownerId == currentUserId;
                  final otherPartyId = isOwner
                      ? widget.chatRoom.finderId
                      : widget.chatRoom.ownerId;
                  final otherPartyName = isOwner
                      ? widget.chatRoom.finderName
                      : widget.chatRoom.ownerName;

                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) => RatingDialog(
                      userId: otherPartyId,
                      userName: otherPartyName,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to resolve: $e'),
                      backgroundColor: AppTheme.lostColor,
                    ),
                  );
                }
              }
            },
            child: const Text(
              'Confirm',
              style: TextStyle(color: AppTheme.foundColor),
            ),
          ),
        ],
      ),
    );
  }

  void _showSafeHandoverBottomSheet(
    BuildContext context,
    double midLat,
    double midLon,
    FirebaseService firebaseService,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (bottomSheetContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.65,
              minChildSize: 0.4,
              maxChildSize: 0.9,
              expand: false,
              builder: (context, scrollController) {
                return FutureBuilder<List<SafeSpot>>(
                  future: SafePlacesService.getNearbySafeSpots(midLat, midLon),
                  builder: (context, snapshot) {
                    final isLoading =
                        snapshot.connectionState == ConnectionState.waiting;
                    final spots = snapshot.data ?? [];

                    return ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      children: [
                        // Handle bar
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: AppTheme.border,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Title
                        Row(
                          children: const [
                            Icon(
                              Icons.shield_rounded,
                              color: AppTheme.foundColor,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Safe Handover Spots',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'These locations are recommended public meeting points near the calculated midpoint between you and the other user.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Safety checklist card
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.darkBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Safety Guidelines',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.secondary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              _buildChecklistItem(
                                'Meet in a public, well-lit place (e.g. police lobbies, cafes).',
                              ),
                              _buildChecklistItem(
                                'Prefer daylight meeting times.',
                              ),
                              _buildChecklistItem(
                                'Consider bringing a friend with you.',
                              ),
                              _buildChecklistItem(
                                'Thoroughly inspect the item before finalizing.',
                              ),
                              _buildChecklistItem(
                                'Never send reward money or payment before meeting.',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Midpoint coordinates info
                        Text(
                          'Midpoint: ${midLat.toStringAsFixed(5)}, ${midLon.toStringAsFixed(5)}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        const Divider(color: AppTheme.border, height: 24),

                        // Loading / List of spots
                        if (isLoading)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(32.0),
                              child: CircularProgressIndicator(
                                color: AppTheme.primary,
                              ),
                            ),
                          )
                        else if (spots.isEmpty)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Text(
                                'No specific spots found nearby.',
                                style: TextStyle(color: AppTheme.textMuted),
                              ),
                            ),
                          )
                        else
                          ...spots.map((spot) {
                            final distText = spot.distanceInMeters < 1000
                                ? '${spot.distanceInMeters.round()} m'
                                : '${(spot.distanceInMeters / 1000).toStringAsFixed(1)} km';

                            IconData icon;
                            Color iconColor;
                            if (spot.category.contains('Police')) {
                              icon = Icons.local_police_rounded;
                              iconColor = Colors.blue;
                            } else if (spot.category.contains('Cafe')) {
                              icon = Icons.local_cafe_rounded;
                              iconColor = Colors.orange;
                            } else {
                              icon = Icons.store_rounded;
                              iconColor = AppTheme.secondary;
                            }

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              color: AppTheme.cardBg,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: AppTheme.border),
                              ),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: iconColor.withValues(alpha: 0.12),
                                  child: Icon(icon, color: iconColor, size: 20),
                                ),
                                title: Text(
                                  spot.name,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                subtitle: Text(
                                  '${spot.category} • $distText away',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                                trailing: ElevatedButton(
                                  onPressed: () {
                                    final name =
                                        firebaseService
                                            .currentUser
                                            ?.displayName ??
                                        'Anonymous';
                                    final proposeText =
                                        '🤝 Proposed Handover Meeting Spot:\n📍 Name: ${spot.name}\n🌐 Category: ${spot.category}\n📏 Distance from midpoint: $distText';
                                    firebaseService.sendMessage(
                                      widget.chatRoom.id,
                                      proposeText,
                                      name,
                                    );
                                    Navigator.pop(bottomSheetContext);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Proposed meeting at ${spot.name}!',
                                        ),
                                        backgroundColor: AppTheme.foundColor,
                                      ),
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 4,
                                    ),
                                    backgroundColor: AppTheme.primary,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: const Text(
                                    'Propose',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                ),
                              ),
                            );
                          }),
                      ],
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  void _openSafeSpotsSheet(BuildContext context, FirebaseService firebaseService) async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 4),
      );
      if (context.mounted) {
        _showSafeHandoverBottomSheet(context, pos.latitude, pos.longitude, firebaseService);
      }
    } catch (_) {
      if (context.mounted) {
        _showSafeHandoverBottomSheet(context, 28.6139, 77.2090, firebaseService);
      }
    }
  }

  Widget _buildChecklistItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.check_circle_outline_rounded,
            size: 14,
            color: AppTheme.foundColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  final List<String> _quickReplies = [
    'On my way! 🏃‍♂️',
    'I have arrived. 📍',
    'Can we meet in a public space? 🤝',
    'Propose Safe Spot 🛡️',
    'Can you send another photo? 📸',
    'Thank you! 🙏',
  ];

  @override
  Widget build(BuildContext context) {
    final firebaseService = Provider.of<FirebaseService>(context);
    final String currentUserId = firebaseService.currentUserId ?? '';
    final isOwner = widget.chatRoom.ownerId == currentUserId;
    final otherPartyName = isOwner
        ? widget.chatRoom.finderName
        : widget.chatRoom.ownerName;

    return StreamBuilder<List<ChatRoomModel>>(
      stream: firebaseService.getUserChatRooms(),
      builder: (context, chatSnapshot) {
        final rooms = chatSnapshot.data;
        final room =
            rooms?.where((r) => r.id == widget.chatRoom.id).firstOrNull ??
            widget.chatRoom;

        final Map<String, dynamic>? liveCoords = room.liveLocations;
        final bool anyLocationSharing =
            liveCoords != null && liveCoords.isNotEmpty;

        return Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            title: Row(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 19,
                      backgroundColor: AppTheme.primary.withValues(alpha: 0.2),
                      child: Text(
                        otherPartyName.isNotEmpty ? otherPartyName[0].toUpperCase() : '?',
                        style: const TextStyle(
                          color: AppTheme.primaryAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: AppTheme.foundColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.darkBg, width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        otherPartyName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppTheme.secondary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: AppTheme.secondary.withValues(alpha: 0.3),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          widget.chatRoom.itemTitle,
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.secondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              // Live Location Toggle Button
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: _isSharingLocation
                      ? AppTheme.lostColor.withValues(alpha: 0.15)
                      : AppTheme.cardBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _isSharingLocation
                        ? AppTheme.lostColor.withValues(alpha: 0.5)
                        : AppTheme.border,
                    width: 1,
                  ),
                ),
                child: IconButton(
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(),
                  icon: Icon(
                    _isSharingLocation
                        ? Icons.location_disabled_rounded
                        : Icons.my_location_rounded,
                    color: _isSharingLocation
                        ? AppTheme.lostColor
                        : AppTheme.secondary,
                    size: 19,
                  ),
                  tooltip: _isSharingLocation
                      ? 'Stop Sharing Location'
                      : 'Share Live Location',
                  onPressed: () => _toggleLocationSharing(firebaseService),
                ),
              ),
              const SizedBox(width: 6),
              // Call Button
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.cardBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.border, width: 1),
                ),
                child: IconButton(
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(),
                  icon: const Icon(
                    Icons.phone_rounded,
                    color: AppTheme.secondary,
                    size: 19,
                  ),
                  tooltip: 'Voice Call',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CallOverlayPage(
                          chatRoomId: widget.chatRoom.id,
                          otherPartyName: otherPartyName,
                          isCaller: true,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 6),
              // Resolve button only if current user is owner or finder
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 8, right: 10),
                decoration: BoxDecoration(
                  color: AppTheme.cardBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.border, width: 1),
                ),
                child: IconButton(
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(),
                  icon: const Icon(
                    Icons.check_circle_rounded,
                    color: AppTheme.foundColor,
                    size: 19,
                  ),
                  tooltip: 'Mark Resolved',
                  onPressed: () => _resolveItem(firebaseService),
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              // Safety Tip & Meeting Spot Banner
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.secondary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.secondary.withValues(alpha: 0.25),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppTheme.secondary.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.shield_outlined,
                        color: AppTheme.secondary,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Coordinate handovers in safe, public places.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => _openSafeSpotsSheet(context, firebaseService),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.secondary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.place_rounded, size: 12, color: AppTheme.secondary),
                            SizedBox(width: 4),
                            Text(
                              'Safe Spots',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.secondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Live Location Map Banner
              if (anyLocationSharing)
                Container(
                  height: 150,
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.border, width: 1.5),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Builder(
                    builder: (context) {
                      LatLng? point1;
                      LatLng? point2;
                      String? distanceText;
                      String? etaText;

                      if (liveCoords.length == 2) {
                        final keys = liveCoords.keys.toList();
                        final loc1 = liveCoords[keys[0]];
                        final loc2 = liveCoords[keys[1]];
                        point1 = LatLng(
                          (loc1['latitude'] as num).toDouble(),
                          (loc1['longitude'] as num).toDouble(),
                        );
                        point2 = LatLng(
                          (loc2['latitude'] as num).toDouble(),
                          (loc2['longitude'] as num).toDouble(),
                        );

                        final double distanceInMeters =
                            Geolocator.distanceBetween(
                              point1.latitude,
                              point1.longitude,
                              point2.latitude,
                              point2.longitude,
                            );

                        if (distanceInMeters < 1000) {
                          distanceText = '${distanceInMeters.round()} m';
                        } else {
                          distanceText =
                              '${(distanceInMeters / 1000).toStringAsFixed(1)} km';
                        }

                        final int etaMinutes = (distanceInMeters / 84).round();
                        etaText = etaMinutes <= 1
                            ? '< 1 min walk'
                            : '$etaMinutes min walk';

                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (distanceInMeters < 10) {
                            _chatMapController?.animateCamera(
                              CameraUpdate.newLatLngZoom(point1!, 15.0),
                            );
                          } else {
                            final southLat = point1!.latitude < point2!.latitude
                                ? point1.latitude
                                : point2.latitude;
                            final northLat = point1.latitude > point2.latitude
                                ? point1.latitude
                                : point2.latitude;
                            final westLng = point1.longitude < point2.longitude
                                ? point1.longitude
                                : point2.longitude;
                            final eastLng = point1.longitude > point2.longitude
                                ? point1.longitude
                                : point2.longitude;
                            _chatMapController?.animateCamera(
                              CameraUpdate.newLatLngBounds(
                                LatLngBounds(
                                  southwest: LatLng(southLat, westLng),
                                  northeast: LatLng(northLat, eastLng),
                                ),
                                40.0,
                              ),
                            );
                          }
                        });
                      } else if (liveCoords.length == 1) {
                        final loc = liveCoords.values.first;
                        final point = LatLng(
                          (loc['latitude'] as num).toDouble(),
                          (loc['longitude'] as num).toDouble(),
                        );
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _chatMapController?.animateCamera(
                            CameraUpdate.newLatLngZoom(point, 15.0),
                          );
                        });
                      }

                      final initialTarget = LatLng(
                        (liveCoords.values.first['latitude'] as num).toDouble(),
                        (liveCoords.values.first['longitude'] as num).toDouble(),
                      );

                      final liveMarkers = liveCoords.entries.map((entry) {
                        final uid = entry.key;
                        final data = entry.value;
                        final isMe = uid == currentUserId;
                        return Marker(
                          markerId: MarkerId(uid),
                          position: LatLng(
                            (data['latitude'] as num).toDouble(),
                            (data['longitude'] as num).toDouble(),
                          ),
                          icon: BitmapDescriptor.defaultMarkerWithHue(
                            isMe ? BitmapDescriptor.hueViolet : BitmapDescriptor.hueCyan,
                          ),
                          infoWindow: InfoWindow(title: isMe ? 'Me' : otherPartyName),
                        );
                      }).toSet();

                      final livePolylines = (point1 != null && point2 != null)
                          ? {
                              Polyline(
                                polylineId: const PolylineId('live_connection'),
                                points: [point1, point2],
                                color: AppTheme.primary,
                                width: 3,
                                patterns: [PatternItem.dash(20), PatternItem.gap(10)],
                              ),
                            }
                          : <Polyline>{};

                      return Stack(
                        children: [
                          GoogleMap(
                            style: GoogleMapsService.darkMapStyle,
                            initialCameraPosition: CameraPosition(
                              target: initialTarget,
                              zoom: 15.0,
                            ),
                            onMapCreated: (controller) {
                              _chatMapController = controller;
                            },
                            markers: liveMarkers,
                            polylines: livePolylines,
                            myLocationEnabled: false,
                            myLocationButtonEnabled: false,
                            zoomControlsEnabled: false,
                            mapToolbarEnabled: false,
                          ),
                          if (distanceText != null && etaText != null)
                            Positioned(
                              bottom: 8,
                              left: 8,
                              right: 8,
                              child: GlassCard(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                borderRadius: 10,
                                opacity: 0.15,
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.directions_walk_rounded,
                                      size: 14,
                                      color: AppTheme.secondary,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        '$distanceText away • $etaText',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.textPrimary,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    TextButton.icon(
                                      onPressed: () {
                                        if (point1 != null && point2 != null) {
                                          final double midLat =
                                              (point1.latitude +
                                                  point2.latitude) /
                                              2;
                                          final double midLon =
                                              (point1.longitude +
                                                  point2.longitude) /
                                              2;
                                          _showSafeHandoverBottomSheet(
                                            context,
                                            midLat,
                                            midLon,
                                            firebaseService,
                                          );
                                        }
                                      },
                                      icon: const Icon(
                                        Icons.security_rounded,
                                        size: 12,
                                        color: AppTheme.foundColor,
                                      ),
                                      label: const Text(
                                        'Safe Spots',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: AppTheme.foundColor,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),

              // Message Stream
              Expanded(
                child: StreamBuilder<List<MessageModel>>(
                  stream: firebaseService.getChatMessages(widget.chatRoom.id),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final messages = snapshot.data ?? [];

                    if (messages.isEmpty) {
                      return Center(
                        child: Text(
                          'Start the conversation with $otherPartyName',
                          style: const TextStyle(color: AppTheme.textMuted),
                        ),
                      );
                    }

                    return ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      padding: const EdgeInsets.all(16),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final msg = messages[index];
                        final isMe = msg.senderId == currentUserId;
                        final bubbleBg = isMe
                            ? AppTheme.primary
                            : AppTheme.cardBg;
                        final alignment = isMe
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start;
                        final timeStr = DateFormat(
                          'hh:mm a',
                        ).format(msg.timestamp);

                        final isVerification = msg.text.startsWith('🔑 Verification') ||
                            msg.text.startsWith('🔑');
                        final isHandoverSpot = msg.text.contains('Proposed Handover Meeting Spot') ||
                            msg.text.startsWith('🤝 Proposed');

                        final Color bubbleBorderColor = isHandoverSpot
                            ? AppTheme.foundColor
                            : (isVerification ? const Color(0xFFF59E0B) : AppTheme.border);
                        final Color bubbleCardColor = isHandoverSpot
                            ? const Color(0xFF0F241A)
                            : (isVerification ? const Color(0xFF1E1B18) : bubbleBg);

                        return Column(
                          crossAxisAlignment: alignment,
                          children: [
                            Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.75,
                              ),
                              decoration: BoxDecoration(
                                color: bubbleCardColor,
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(16),
                                  topRight: const Radius.circular(16),
                                  bottomLeft: isMe
                                      ? const Radius.circular(16)
                                      : Radius.zero,
                                  bottomRight: isMe
                                      ? Radius.zero
                                      : const Radius.circular(16),
                                ),
                                border: Border.all(
                                  color: bubbleBorderColor,
                                  width: (isHandoverSpot || isVerification) ? 1.4 : 0.8,
                                ),
                                boxShadow: (isHandoverSpot || isVerification)
                                    ? [
                                        BoxShadow(
                                          color: bubbleBorderColor.withValues(alpha: 0.15),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Builder(
                                builder: (context) {
                                  final isLocation = msg.latitude != null && msg.longitude != null;
                                  if (isLocation) {
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Mini Map
                                        Container(
                                          height: 120,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: AppTheme.border, width: 0.5),
                                          ),
                                          clipBehavior: Clip.antiAlias,
                                          child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              CachedNetworkImage(
                                                imageUrl: GoogleMapsService.getStaticMapUrl(
                                                  lat: msg.latitude!,
                                                  lng: msg.longitude!,
                                                  zoom: 15,
                                                  width: 400,
                                                  height: 240,
                                                  isLost: true,
                                                ),
                                                fit: BoxFit.cover,
                                                placeholder: (context, url) => Container(
                                                  color: AppTheme.darkBg,
                                                  child: const Center(
                                                    child: CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: AppTheme.secondary,
                                                    ),
                                                  ),
                                                ),
                                                errorWidget: (context, url, error) => Container(
                                                  color: AppTheme.darkBg,
                                                  child: const Center(
                                                    child: Icon(Icons.map, color: AppTheme.textMuted),
                                                  ),
                                                ),
                                              ),
                                              Positioned(
                                                top: 6,
                                                right: 6,
                                                child: InkWell(
                                                  onTap: () {
                                                    StreetViewDialog.show(
                                                      context,
                                                      latitude: msg.latitude!,
                                                      longitude: msg.longitude!,
                                                      locationTitle: msg.locationName ?? 'Shared Location',
                                                    );
                                                  },
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color: Colors.black.withValues(alpha: 0.7),
                                                      borderRadius: BorderRadius.circular(6),
                                                      border: Border.all(color: Colors.white24, width: 0.5),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: const [
                                                        Icon(Icons.streetview_rounded, size: 12, color: AppTheme.secondary),
                                                        SizedBox(width: 4),
                                                        Text('Street View', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        // Location Title
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.place_rounded,
                                              color: AppTheme.secondary,
                                              size: 16,
                                            ),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                msg.locationName ?? 'Shared Location',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                  color: AppTheme.textPrimary,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        // Navigate Button
                                        SizedBox(
                                          width: double.infinity,
                                          height: 32,
                                          child: ElevatedButton.icon(
                                            onPressed: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) => LocationNavigationPage(
                                                    destinationCoords: LatLng(msg.latitude!, msg.longitude!),
                                                    destinationName: msg.locationName ?? 'Shared Location',
                                                  ),
                                                ),
                                              );
                                            },
                                            icon: const Icon(Icons.directions_rounded, size: 14),
                                            label: const Text(
                                              'Navigate',
                                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                            ),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: AppTheme.primary,
                                              padding: EdgeInsets.zero,
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Align(
                                          alignment: Alignment.bottomRight,
                                          child: Text(
                                            timeStr,
                                            style: TextStyle(
                                              fontSize: 9,
                                              color: isMe
                                                  ? Colors.white.withValues(alpha: 0.7)
                                                  : AppTheme.textMuted,
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  }

                                  if (isVerification) {
                                    String questionText = msg.text;
                                    if (questionText.startsWith('🔑 Verification Question:')) {
                                      questionText = questionText.replaceFirst('🔑 Verification Question:', '').trim();
                                    } else if (questionText.startsWith('🔑 Verification:')) {
                                      questionText = questionText.replaceFirst('🔑 Verification:', '').trim();
                                    } else if (questionText.startsWith('🔑')) {
                                      questionText = questionText.replaceFirst('🔑', '').trim();
                                    }

                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(4),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: const Icon(
                                                Icons.vpn_key_rounded,
                                                size: 13,
                                                color: Color(0xFFFBBF24),
                                              ),
                                            ),
                                            const SizedBox(width: 7),
                                            const Text(
                                              'VERIFICATION QUESTION',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w900,
                                                letterSpacing: 0.6,
                                                color: Color(0xFFFBBF24),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: AppTheme.darkBg,
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(
                                              color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                                              width: 0.8,
                                            ),
                                          ),
                                          child: Text(
                                            questionText,
                                            style: const TextStyle(
                                              color: AppTheme.textPrimary,
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w600,
                                              height: 1.3,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.security_rounded,
                                              size: 11,
                                              color: AppTheme.textMuted,
                                            ),
                                            const SizedBox(width: 4),
                                            const Expanded(
                                              child: Text(
                                                'Answer to confirm ownership',
                                                style: TextStyle(
                                                  fontSize: 9.5,
                                                  color: AppTheme.textMuted,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              timeStr,
                                              style: const TextStyle(
                                                fontSize: 9,
                                                color: AppTheme.textMuted,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    );
                                  }

                                  if (isHandoverSpot) {
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(4),
                                              decoration: BoxDecoration(
                                                color: AppTheme.foundColor.withValues(alpha: 0.2),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: const Icon(
                                                Icons.handshake_rounded,
                                                size: 13,
                                                color: AppTheme.foundColor,
                                              ),
                                            ),
                                            const SizedBox(width: 7),
                                            const Text(
                                              'SAFE HANDOVER PROPOSAL',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w900,
                                                letterSpacing: 0.6,
                                                color: AppTheme.foundColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: AppTheme.darkBg,
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(
                                              color: AppTheme.foundColor.withValues(alpha: 0.3),
                                              width: 0.8,
                                            ),
                                          ),
                                          child: Text(
                                            msg.text,
                                            style: const TextStyle(
                                              color: AppTheme.textPrimary,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                              height: 1.35,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            InkWell(
                                              onTap: () => _openSafeSpotsSheet(context, firebaseService),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: const [
                                                  Icon(Icons.swap_horiz_rounded, size: 12, color: AppTheme.secondary),
                                                  SizedBox(width: 3),
                                                  Text(
                                                    'Suggest Alternate',
                                                    style: TextStyle(fontSize: 10, color: AppTheme.secondary, fontWeight: FontWeight.bold),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const Spacer(),
                                            Text(
                                              timeStr,
                                              style: const TextStyle(
                                                fontSize: 9,
                                                color: AppTheme.textMuted,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    );
                                  }

                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        msg.text,
                                        style: const TextStyle(
                                          color: AppTheme.textPrimary,
                                          fontSize: 14.5,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Align(
                                        alignment: Alignment.bottomRight,
                                        child: Text(
                                          timeStr,
                                          style: TextStyle(
                                            fontSize: 9,
                                            color: isMe
                                                ? Colors.white.withValues(alpha: 0.7)
                                                : AppTheme.textMuted,
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),

              // Handover templates bar
              Container(
                height: 38,
                margin: const EdgeInsets.only(top: 4, bottom: 6),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  itemCount: _quickReplies.length,
                  itemBuilder: (context, index) {
                    final replyText = _quickReplies[index];
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: InkWell(
                        onTap: () {
                          if (replyText.contains('Safe Spot')) {
                            _openSafeSpotsSheet(context, firebaseService);
                          } else {
                            _messageController.text = replyText;
                            _send(firebaseService);
                          }
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: AppTheme.cardBg,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppTheme.secondary.withValues(alpha: 0.35),
                              width: 1,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              replyText,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Modern Floating Message Input Box
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                decoration: BoxDecoration(
                  color: AppTheme.cardBg.withValues(alpha: 0.95),
                  border: Border(top: BorderSide(color: AppTheme.border, width: 0.8)),
                ),
                child: Row(
                  children: [
                    // Share location button
                    Container(
                      decoration: BoxDecoration(
                        color: AppTheme.secondary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.secondary.withValues(alpha: 0.3)),
                      ),
                      child: IconButton(
                        icon: const Icon(
                          Icons.add_location_alt_rounded,
                          color: AppTheme.secondary,
                          size: 19,
                        ),
                        tooltip: 'Share Meeting Location',
                        onPressed: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const LocationPickerPage(),
                            ),
                          );
                          if (result != null && result is Map<String, dynamic> && mounted) {
                            final lat = result['latitude'] as double;
                            final lon = result['longitude'] as double;
                            final name = result['name'] as String;
                            final senderName = firebaseService.currentUser?.displayName ?? 'Anonymous';
                            
                            await firebaseService.sendMessage(
                              widget.chatRoom.id,
                              'Shared location: $name',
                              senderName,
                              latitude: lat,
                              longitude: lon,
                              locationName: name,
                            );
                            
                            _scrollController.animateTo(
                              0.0,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOut,
                            );
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Safe Spots shortcut button
                    Container(
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                      ),
                      child: IconButton(
                        icon: const Icon(
                          Icons.shield_rounded,
                          color: AppTheme.primaryAccent,
                          size: 19,
                        ),
                        tooltip: 'Suggest Safe Meetup Spot',
                        onPressed: () => _openSafeSpotsSheet(context, firebaseService),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        textCapitalization: TextCapitalization.sentences,
                        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Type a message...',
                          hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          filled: true,
                          fillColor: AppTheme.darkBg,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: const BorderSide(
                              color: AppTheme.border,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: const BorderSide(
                              color: AppTheme.border,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: const BorderSide(
                              color: AppTheme.primary,
                              width: 1.5,
                            ),
                          ),
                        ),
                        onSubmitted: (_) => _send(firebaseService),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          )
                        ],
                      ),
                      child: IconButton(
                        icon: const Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                        onPressed: () => _send(firebaseService),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import '../models/chat_model.dart';
import '../services/firebase_service.dart';
import '../theme/app_theme.dart';
import 'call_overlay_page.dart';
import '../widgets/rating_dialog.dart';
import '../widgets/glass_card.dart';
import '../services/safe_places_service.dart';
import '../widgets/cached_tile_provider.dart';
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
  final MapController _chatMapController = MapController();

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

  @override
  void dispose() {
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
                                  backgroundColor: iconColor.withOpacity(0.12),
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
                          }).toList(),
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
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  otherPartyName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Re: ${widget.chatRoom.itemTitle}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.secondary,
                  ),
                ),
              ],
            ),
            actions: [
              // Live Location Toggle Button
              IconButton(
                icon: Icon(
                  _isSharingLocation
                      ? Icons.location_disabled_rounded
                      : Icons.my_location_rounded,
                  color: _isSharingLocation
                      ? AppTheme.lostColor
                      : AppTheme.secondary,
                ),
                tooltip: _isSharingLocation
                    ? 'Stop Sharing Location'
                    : 'Share Location',
                onPressed: () => _toggleLocationSharing(firebaseService),
              ),
              // Call Button
              IconButton(
                icon: const Icon(
                  Icons.phone_rounded,
                  color: AppTheme.secondary,
                ),
                tooltip: 'Call',
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
              // Resolve button only if current user is owner or finder
              IconButton(
                icon: const Icon(
                  Icons.check_circle_rounded,
                  color: AppTheme.foundColor,
                ),
                tooltip: 'Mark Resolved',
                onPressed: () => _resolveItem(firebaseService),
              ),
            ],
          ),
          body: Column(
            children: [
              // Safety Tip Banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                color: AppTheme.secondary.withOpacity(0.08),
                child: Row(
                  children: const [
                    Icon(
                      Icons.shield_outlined,
                      color: AppTheme.secondary,
                      size: 16,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Safety tip: Coordinate handovers in public, well-lit spaces.',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
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
                            _chatMapController.move(point1!, 15.0);
                          } else {
                            _chatMapController.fitCamera(
                              CameraFit.bounds(
                                bounds: LatLngBounds.fromPoints([
                                  point1!,
                                  point2!,
                                ]),
                                padding: const EdgeInsets.all(32.0),
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
                          _chatMapController.move(point, 15.0);
                        });
                      }

                      return Stack(
                        children: [
                          FlutterMap(
                            mapController: _chatMapController,
                            options: MapOptions(
                              initialCenter: LatLng(
                                (liveCoords.values.first['latitude'] as num)
                                    .toDouble(),
                                (liveCoords.values.first['longitude'] as num)
                                    .toDouble(),
                              ),
                              initialZoom: 15.0,
                            ),
                            children: [
                              TileLayer(
                                urlTemplate:
                                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.example.dhundo',
                                tileProvider: CachedTileProvider(),
                              ),
                              if (point1 != null && point2 != null)
                                PolylineLayer(
                                  polylines: [
                                    Polyline(
                                      points: [point1, point2],
                                      color: AppTheme.primary,
                                      strokeWidth: 3.0,
                                      isDotted: true,
                                    ),
                                  ],
                                ),
                              MarkerLayer(
                                markers: liveCoords.entries.map((entry) {
                                  final uid = entry.key;
                                  final data = entry.value;
                                  final isMe = uid == currentUserId;
                                  return Marker(
                                    point: LatLng(
                                      (data['latitude'] as num).toDouble(),
                                      (data['longitude'] as num).toDouble(),
                                    ),
                                    width: 50,
                                    height: 50,
                                    child: Column(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppTheme.cardBg,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            border: Border.all(
                                              color: isMe
                                                  ? AppTheme.primary
                                                  : AppTheme.secondary,
                                              width: 0.8,
                                            ),
                                          ),
                                          child: Text(
                                            isMe ? 'Me' : otherPartyName,
                                            style: const TextStyle(
                                              fontSize: 8,
                                              fontWeight: FontWeight.bold,
                                              color: AppTheme.textPrimary,
                                            ),
                                          ),
                                        ),
                                        Icon(
                                          Icons.location_pin,
                                          color: isMe
                                              ? AppTheme.primary
                                              : AppTheme.secondary,
                                          size: 26,
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
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

                        final isVerification = msg.text.startsWith(
                          '🔑 Verification',
                        );

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
                                color: isVerification
                                    ? Colors.teal.withOpacity(0.12)
                                    : bubbleBg,
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
                                  color: isVerification
                                      ? Colors.teal
                                      : AppTheme.border,
                                  width: isVerification ? 1.2 : 0.8,
                                ),
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
                                          height: 110,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: AppTheme.border, width: 0.5),
                                          ),
                                          clipBehavior: Clip.antiAlias,
                                          child: FlutterMap(
                                            options: MapOptions(
                                              initialCenter: LatLng(msg.latitude!, msg.longitude!),
                                              initialZoom: 14.0,
                                              interactionOptions: const InteractionOptions(
                                                flags: InteractiveFlag.none,
                                              ),
                                            ),
                                            children: [
                                              TileLayer(
                                                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                                userAgentPackageName: 'com.example.dhundo',
                                                tileProvider: CachedTileProvider(),
                                              ),
                                              MarkerLayer(
                                                markers: [
                                                  Marker(
                                                    point: LatLng(msg.latitude!, msg.longitude!),
                                                    width: 30,
                                                    height: 30,
                                                    child: const Icon(
                                                      Icons.location_pin,
                                                      color: AppTheme.lostColor,
                                                      size: 24,
                                                    ),
                                                  ),
                                                ],
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
                                                  ? Colors.white.withOpacity(0.7)
                                                  : AppTheme.textMuted,
                                            ),
                                          ),
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
                                                ? Colors.white.withOpacity(0.7)
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
                height: 36,
                margin: const EdgeInsets.only(top: 4, bottom: 4),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _quickReplies.length,
                  itemBuilder: (context, index) {
                    final replyText = _quickReplies[index];
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ActionChip(
                        label: Text(
                          replyText,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        backgroundColor: AppTheme.cardBg,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: const BorderSide(color: AppTheme.border),
                        ),
                        onPressed: () {
                          _messageController.text = replyText;
                          _send(firebaseService);
                        },
                      ),
                    );
                  },
                ),
              ),

              // Message Input Box
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: AppTheme.cardBg,
                      child: IconButton(
                        icon: const Icon(
                          Icons.add_location_alt_rounded,
                          color: AppTheme.secondary,
                          size: 20,
                        ),
                        tooltip: 'Share Location',
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
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        textCapitalization: TextCapitalization.sentences,
                        style: const TextStyle(color: AppTheme.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'Type a message...',
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          fillColor: AppTheme.cardBg,
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
                            ),
                          ),
                        ),
                        onSubmitted: (_) => _send(firebaseService),
                      ),
                    ),
                    const SizedBox(width: 8),
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: AppTheme.primary,
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

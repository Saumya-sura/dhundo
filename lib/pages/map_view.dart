import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../models/item_model.dart';
import '../services/firebase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import 'chat_page.dart';
import '../widgets/cached_tile_provider.dart';

class MapView extends StatefulWidget {
  const MapView({super.key});

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  final MapController _mapController = MapController();
  LatLng _currentCenter = const LatLng(28.6139, 77.2090); // Default to New Delhi
  bool _locating = true;
  ItemModel? _selectedItem;
  String _selectedCategory = 'All';

  final List<String> _categories = [
    'All',
    'Electronics',
    'Keys',
    'Wallets',
    'Documents',
    'Pets',
    'Clothing',
    'Others'
  ];

  @override
  void initState() {
    super.initState();
    _determinePosition();
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    try {
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        setState(() => _locating = false);
        return;
      }

      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (!mounted) return;
          setState(() => _locating = false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() => _locating = false);
        return;
      }

      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _currentCenter = LatLng(position.latitude, position.longitude);
        _locating = false;
      });
      _mapController.move(_currentCenter, 14.0);
    } catch (_) {
      if (!mounted) return;
      setState(() => _locating = false);
    }
  }

  void _navigateToChat(ItemModel item, FirebaseService firebaseService) async {
    if (item.reporterId == firebaseService.currentUserId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("This is your report!"),
          backgroundColor: AppTheme.primary,
        ),
      );
      return;
    }

    // Ownership Verification Check
    if (item.verificationQuestion != null && item.verificationQuestion!.trim().isNotEmpty) {
      final answerController = TextEditingController();
      final hasAnswered = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: AppTheme.cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppTheme.border, width: 1.5),
          ),
          title: Row(
            children: const [
              Icon(Icons.key_rounded, color: AppTheme.secondary),
              SizedBox(width: 8),
              Text('Verification Required', style: TextStyle(fontSize: 18)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'The reporter requires ownership verification before you can chat.',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 16),
              Text(
                'Question: ${item.verificationQuestion}',
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: answerController,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Type your answer here...',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () {
                if (answerController.text.trim().isNotEmpty) {
                  Navigator.pop(dialogContext, true);
                } else {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('Please enter an answer.')),
                  );
                }
              },
              child: const Text('Submit'),
            ),
          ],
        ),
      );

      if (hasAnswered != true) return;

      try {
        final currentUserName = firebaseService.currentUser?.displayName ?? 'Anonymous';
        final chatRoom = await firebaseService.getOrCreateChatRoom(
          itemId: item.id,
          itemTitle: item.title,
          itemIsLost: item.isLost,
          ownerId: item.isLost ? item.reporterId : firebaseService.currentUserId!,
          ownerName: item.isLost ? item.reporterName : currentUserName,
          finderId: item.isLost ? firebaseService.currentUserId! : item.reporterId,
          finderName: item.isLost ? currentUserName : item.reporterName,
        );

        // Send the verification answer message automatically
        final answerText = answerController.text.trim();
        final verificationMsg = '🔑 Verification Attempt:\nQuestion: ${item.verificationQuestion}\nClaimant\'s Answer: $answerText';
        await firebaseService.sendMessage(chatRoom.id, verificationMsg, currentUserName);

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatPage(chatRoom: chatRoom),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error initiating chat: $e'),
              backgroundColor: AppTheme.lostColor,
            ),
          );
        }
      }
      return;
    }

    try {
      final currentUserName = firebaseService.currentUser?.displayName ?? 'Anonymous';
      final chatRoom = await firebaseService.getOrCreateChatRoom(
        itemId: item.id,
        itemTitle: item.title,
        itemIsLost: item.isLost,
        ownerId: item.isLost ? item.reporterId : firebaseService.currentUserId!,
        ownerName: item.isLost ? item.reporterName : currentUserName,
        finderId: item.isLost ? firebaseService.currentUserId! : item.reporterId,
        finderName: item.isLost ? currentUserName : item.reporterName,
      );

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatPage(chatRoom: chatRoom),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error initiating chat: $e'),
            backgroundColor: AppTheme.lostColor,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final firebaseService = Provider.of<FirebaseService>(context);

    return Scaffold(
      body: StreamBuilder<List<ItemModel>>(
        stream: firebaseService.getItems(),
        builder: (context, snapshot) {
          List<ItemModel> items = snapshot.data ?? [];
          
          // Filter items based on category and status
          List<ItemModel> activeItems = items.where((i) => i.status == 'active').toList();
          
          if (_selectedCategory != 'All') {
            activeItems = activeItems.where((i) => i.category == _selectedCategory).toList();
          }

          final markers = activeItems.map((item) {
            final color = item.isLost ? AppTheme.lostColor : AppTheme.foundColor;
            return Marker(
              point: LatLng(item.latitude, item.longitude),
              width: item.isAmberAlert ? 60 : 50,
              height: item.isAmberAlert ? 60 : 50,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedItem = item;
                  });
                  _mapController.move(LatLng(item.latitude, item.longitude), 15.0);
                },
                child: item.isAmberAlert
                    ? PulsingAmberMarker(color: color)
                    : Icon(
                        item.isLost ? Icons.location_on_rounded : Icons.radar_rounded,
                        color: color,
                        size: 38,
                        shadows: [
                          Shadow(
                            color: color.withOpacity(0.6),
                            blurRadius: 8,
                          )
                        ],
                      ),
              ),
            );
          }).toList();

          return Stack(
            children: [
              // OpenStreetMap Flutter Map
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _currentCenter,
                  initialZoom: 13.0,
                  onTap: (_, __) {
                    setState(() {
                      _selectedItem = null;
                    });
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.dhundo',
                    tileProvider: CachedTileProvider(),
                  ),
                  MarkerLayer(markers: markers),
                ],
              ),

              // Geolocation Loading Overlay
              if (_locating)
                Positioned(
                  top: 70,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: GlassCard(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      borderRadius: 20,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 10),
                          Text('Getting location...', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ),

              // Top horizontal category chips selector
              Positioned(
                top: 12,
                left: 0,
                right: 0,
                child: SizedBox(
                  height: 46,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _categories.length,
                    itemBuilder: (context, index) {
                      final cat = _categories[index];
                      final isSelected = _selectedCategory == cat;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: FilterChip(
                          label: Text(cat),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              _selectedCategory = cat;
                              _selectedItem = null;
                            });
                          },
                          backgroundColor: AppTheme.cardBg.withOpacity(0.8),
                          selectedColor: AppTheme.primary,
                          checkmarkColor: Colors.white,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : AppTheme.textSecondary,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: isSelected ? AppTheme.primary : AppTheme.border,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              // Bottom card for selected item details
              if (_selectedItem != null)
                Positioned(
                  bottom: 16,
                  left: 16,
                  right: 16,
                  child: GlassCard(
                    padding: const EdgeInsets.all(16),
                    borderRadius: 20,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _selectedItem!.isLost
                                    ? AppTheme.lostColor.withOpacity(0.15)
                                    : AppTheme.foundColor.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _selectedItem!.isLost
                                      ? AppTheme.lostColor
                                      : AppTheme.foundColor,
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                _selectedItem!.isLost ? 'LOST' : 'FOUND',
                                style: TextStyle(
                                  color: _selectedItem!.isLost
                                      ? AppTheme.lostColor
                                      : AppTheme.foundColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _selectedItem!.category,
                              style: const TextStyle(
                                color: AppTheme.secondary,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () {
                                setState(() {
                                  _selectedItem = null;
                                });
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _selectedItem!.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _selectedItem!.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(Icons.location_on_rounded, size: 14, color: AppTheme.textMuted),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _selectedItem!.locationDescription,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Divider(color: AppTheme.border, height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'By ${_selectedItem!.reporterName}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: () => _navigateToChat(_selectedItem!, firebaseService),
                              icon: const Icon(Icons.message_rounded, size: 16),
                              label: Text(
                                _selectedItem!.reporterId == firebaseService.currentUserId
                                    ? 'My Report'
                                    : 'Contact',
                                style: const TextStyle(fontSize: 13),
                              ),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        mini: true,
        backgroundColor: AppTheme.cardBg,
        foregroundColor: AppTheme.textPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppTheme.border, width: 1),
        ),
        onPressed: _determinePosition,
        child: const Icon(Icons.my_location_rounded, size: 18),
      ),
    );
  }
}

class PulsingAmberMarker extends StatefulWidget {
  final Color color;
  const PulsingAmberMarker({super.key, required this.color});

  @override
  State<PulsingAmberMarker> createState() => _PulsingAmberMarkerState();
}

class _PulsingAmberMarkerState extends State<PulsingAmberMarker> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.85, end: 1.25).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _animation,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withOpacity(0.2),
          boxShadow: [
            BoxShadow(
              color: widget.color.withOpacity(0.6),
              blurRadius: 10,
              spreadRadius: 3,
            )
          ],
        ),
        child: Icon(
          Icons.warning_amber_rounded,
          color: widget.color,
          size: 26,
        ),
      ),
    );
  }
}

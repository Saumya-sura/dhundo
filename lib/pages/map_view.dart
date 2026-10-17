import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../models/item_model.dart';
import '../services/firebase_service.dart';
import '../services/google_maps_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/street_view_dialog.dart';
import 'chat_page.dart';

class MapView extends StatefulWidget {
  const MapView({super.key});

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  GoogleMapController? _mapController;
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
      final newCenter = LatLng(position.latitude, position.longitude);
      setState(() {
        _currentCenter = newCenter;
        _locating = false;
      });
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(newCenter, 14.0));
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

      // Save answer in chat upon room creation
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

        await firebaseService.sendMessage(
          chatRoom.id,
          "🔒 Verification Answer: ${answerController.text.trim()}",
          currentUserName,
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

  Set<Marker> _buildMarkers(List<ItemModel> activeItems) {
    return activeItems.map((item) {
      final double hue = item.isAmberAlert
          ? BitmapDescriptor.hueOrange
          : (item.isLost ? BitmapDescriptor.hueRed : BitmapDescriptor.hueGreen);

      return Marker(
        markerId: MarkerId(item.id),
        position: LatLng(item.latitude, item.longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(hue),
        infoWindow: InfoWindow(
          title: item.title,
          snippet: '${item.category} • ${item.isLost ? "LOST" : "FOUND"}',
        ),
        onTap: () {
          setState(() {
            _selectedItem = item;
          });
          _mapController?.animateCamera(
            CameraUpdate.newLatLngZoom(LatLng(item.latitude, item.longitude), 15.0),
          );
        },
      );
    }).toSet();
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

          final markers = _buildMarkers(activeItems);

          return Stack(
            children: [
              // Google Maps View
              GoogleMap(
                style: GoogleMapsService.darkMapStyle,
                initialCameraPosition: CameraPosition(
                  target: _currentCenter,
                  zoom: 13.0,
                ),
                onMapCreated: (controller) {
                  _mapController = controller;
                },
                markers: markers,
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                compassEnabled: true,
                onTap: (_) {
                  setState(() {
                    _selectedItem = null;
                  });
                },
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
                          backgroundColor: AppTheme.cardBg.withValues(alpha: 0.85),
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
                                    ? AppTheme.lostColor.withValues(alpha: 0.15)
                                    : AppTheme.foundColor.withValues(alpha: 0.15),
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
                            // Street View Button
                            OutlinedButton.icon(
                              onPressed: () {
                                StreetViewDialog.show(
                                  context,
                                  latitude: _selectedItem!.latitude,
                                  longitude: _selectedItem!.longitude,
                                  locationTitle: _selectedItem!.title,
                                );
                              },
                              icon: const Icon(Icons.streetview_rounded, size: 16, color: AppTheme.secondary),
                              label: const Text(
                                'Street View',
                                style: TextStyle(fontSize: 12, color: AppTheme.secondary),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppTheme.secondary),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
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

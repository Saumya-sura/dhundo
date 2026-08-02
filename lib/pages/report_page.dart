import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/item_model.dart';
import '../services/firebase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_textfield.dart';
import '../widgets/custom_button.dart';
import 'potential_matches_page.dart';

class ReportPage extends StatefulWidget {
  final bool isActive;
  const ReportPage({super.key, this.isActive = false});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _locDescController = TextEditingController();
  final _imageUrlController = TextEditingController();

  bool _isLost = true;
  String _category = 'Electronics';
  LatLng _selectedCoords = const LatLng(28.6139, 77.2090); // Default Delhi
  bool _loadingLocation = true;
  bool _submitting = false;

  final MapController _miniMapController = MapController();

  final List<String> _categories = [
    'Electronics',
    'Keys',
    'Wallets',
    'Documents',
    'Pets',
    'Clothing',
    'Others'
  ];

  // Preset Unsplash images to make listings beautiful
  final Map<String, String> _presets = {
    'Electronics': 'https://images.unsplash.com/photo-1511707171634-5f897ff02aa9?w=600&auto=format&fit=crop&q=80',
    'Keys': 'https://images.unsplash.com/photo-1582139329536-e7284fece509?w=600&auto=format&fit=crop&q=80',
    'Wallets': 'https://images.unsplash.com/photo-1627124718133-c8d2da0fa6e6?w=600&auto=format&fit=crop&q=80',
    'Documents': 'https://images.unsplash.com/photo-1544947950-fa07a98d237f?w=600&auto=format&fit=crop&q=80',
    'Pets': 'https://images.unsplash.com/photo-1543466835-00a7907e9de1?w=600&auto=format&fit=crop&q=80',
    'Clothing': 'https://images.unsplash.com/photo-1553062407-98eeb64c6a62?w=600&auto=format&fit=crop&q=80',
    'Others': 'https://images.unsplash.com/photo-1584622650111-993a426fbf0a?w=600&auto=format&fit=crop&q=80',
  };

  @override
  void initState() {
    super.initState();
    _fetchCurrentLocation();
    _imageUrlController.text = _presets[_category]!;
  }

  @override
  void didUpdateWidget(covariant ReportPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _fetchCurrentLocation();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _locDescController.dispose();
    _imageUrlController.dispose();
    super.dispose();
  }

  Future<void> _fetchCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    try {
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        setState(() => _loadingLocation = false);
        return;
      }

      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (!mounted) return;
          setState(() => _loadingLocation = false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() => _loadingLocation = false);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (!mounted) return;
      setState(() {
        _selectedCoords = LatLng(position.latitude, position.longitude);
        _loadingLocation = false;
      });
      _miniMapController.move(_selectedCoords, 14.0);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingLocation = false);
    }
  }

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _submitting = true;
    });

    final firebaseService = Provider.of<FirebaseService>(context, listen: false);

    // Create Item object
    final String itemId = const Uuid().v4();
    final item = ItemModel(
      id: itemId,
      title: _titleController.text.trim(),
      description: _descController.text.trim(),
      imageUrl: _imageUrlController.text.trim().isNotEmpty ? _imageUrlController.text.trim() : null,
      latitude: _selectedCoords.latitude,
      longitude: _selectedCoords.longitude,
      locationDescription: _locDescController.text.trim(),
      isLost: _isLost,
      category: _category,
      dateTime: DateTime.now(),
      reporterId: firebaseService.currentUserId!,
      reporterName: firebaseService.currentUser?.displayName ?? 'Anonymous',
    );

    try {
      // Intelligent matching check
      final matches = await firebaseService.checkPotentialMatches(item);

      if (matches.isNotEmpty && mounted) {
        // Show matching alert dialog
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: AppTheme.cardBg,
            title: Row(
              children: const [
                Icon(Icons.radar_rounded, color: AppTheme.secondary),
                SizedBox(width: 8),
                Text('Potential Matches Found!'),
              ],
            ),
            content: Text(
              'We found ${matches.length} reported item(s) in this area that match your details. Would you like to review them first?',
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  Navigator.pop(dialogContext); // Close dialog
                  final wasLost = item.isLost;
                  try {
                    await firebaseService.reportItem(item);
                    _clearForm();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${wasLost ? "Lost" : "Found"} report posted successfully!'),
                          backgroundColor: AppTheme.foundColor,
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Submission failed: $e'),
                          backgroundColor: AppTheme.lostColor,
                        ),
                      );
                    }
                  }
                },
                child: const Text('Submit Anyway', style: TextStyle(color: AppTheme.textSecondary)),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(dialogContext); // Close dialog
                  // Navigate to Matches page and pass the item to review matches
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PotentialMatchesPage(
                        reportedItem: item,
                        potentialMatches: matches,
                      ),
                    ),
                  );
                },
                child: const Text('View Matches'),
              ),
            ],
          ),
        );
      } else {
        final wasLost = _isLost;
        await firebaseService.reportItem(item);
        _clearForm();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${wasLost ? "Lost" : "Found"} report posted successfully!'),
              backgroundColor: AppTheme.foundColor,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Submission failed: $e'),
            backgroundColor: AppTheme.lostColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  void _clearForm() {
    _titleController.clear();
    _descController.clear();
    _locDescController.clear();
    setState(() {
      _isLost = true;
      _category = 'Electronics';
      _imageUrlController.text = _presets[_category]!;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Report Lost or Found Item',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 14),

              // Segmented controls for Lost/Found type
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _isLost = true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _isLost ? AppTheme.lostColor.withOpacity(0.15) : AppTheme.cardBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _isLost ? AppTheme.lostColor : AppTheme.border,
                            width: 1,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            'I LOST SOMETHING',
                            style: TextStyle(
                              color: _isLost ? AppTheme.lostColor : AppTheme.textSecondary,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _isLost = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: !_isLost ? AppTheme.foundColor.withOpacity(0.15) : AppTheme.cardBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: !_isLost ? AppTheme.foundColor : AppTheme.border,
                            width: 1,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            'I FOUND SOMETHING',
                            style: TextStyle(
                              color: !_isLost ? AppTheme.foundColor : AppTheme.textSecondary,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Form fields
              CustomTextField(
                controller: _titleController,
                label: 'Item Title',
                hint: 'e.g. Black Leather Wallet',
                validator: (val) => val == null || val.isEmpty ? 'Title is required' : null,
              ),
              const SizedBox(height: 16),

              // Category Selector dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.darkBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border, width: 1),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButtonFormField<String>(
                    value: _category,
                    dropdownColor: AppTheme.cardBg,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      border: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _category = val;
                          _imageUrlController.text = _presets[val]!;
                        });
                      }
                    },
                    items: _categories.map((cat) {
                      return DropdownMenuItem(value: cat, child: Text(cat));
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              CustomTextField(
                controller: _descController,
                label: 'Description',
                hint: 'Describe details, brands, tags, unique marks...',
                maxLines: 3,
                validator: (val) => val == null || val.isEmpty ? 'Description is required' : null,
              ),
              const SizedBox(height: 16),

              CustomTextField(
                controller: _locDescController,
                label: 'Location Description',
                hint: 'e.g. Near Metro Station exit gate',
                validator: (val) => val == null || val.isEmpty ? 'Location description is required' : null,
              ),
              const SizedBox(height: 16),

              // Image URL text field (preloaded with presets, but allows customizing)
              CustomTextField(
                controller: _imageUrlController,
                label: 'Image URL (Optional)',
                hint: 'Enter photo URL to override category preset',
              ),
              const SizedBox(height: 16),

              // Mini Map Picker
              const Text(
                'Pinpoint Location on Map',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 8),
              Container(
                height: 220,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.border, width: 1),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    FlutterMap(
                      mapController: _miniMapController,
                      options: MapOptions(
                        initialCenter: _selectedCoords,
                        initialZoom: 14.0,
                        onTap: (_, point) {
                          setState(() {
                            _selectedCoords = point;
                          });
                        },
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.example.dhundo',
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _selectedCoords,
                              width: 40,
                              height: 40,
                              child: Icon(
                                _isLost ? Icons.location_on : Icons.radar_rounded,
                                color: _isLost ? AppTheme.lostColor : AppTheme.foundColor,
                                size: 30,
                              ),
                            )
                          ],
                        ),
                      ],
                    ),
                    if (_loadingLocation)
                      Container(
                        color: Colors.black.withOpacity(0.5),
                        child: const Center(
                          child: CircularProgressIndicator(),
                        ),
                      ),
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: FloatingActionButton(
                        heroTag: 'miniMapLocateMe',
                        mini: true,
                        backgroundColor: AppTheme.cardBg,
                        foregroundColor: AppTheme.textPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: AppTheme.border, width: 1),
                        ),
                        onPressed: _fetchCurrentLocation,
                        child: const Icon(Icons.my_location_rounded, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Selected: Lat: ${_selectedCoords.latitude.toStringAsFixed(5)}, Lng: ${_selectedCoords.longitude.toStringAsFixed(5)}',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ),
              const SizedBox(height: 24),

              CustomButton(
                text: _isLost ? 'Report Lost Item' : 'Report Found Item',
                isLoading: _submitting,
                onPressed: _submit,
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

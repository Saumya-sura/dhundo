import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/item_model.dart';
import '../services/firebase_service.dart';
import '../services/google_maps_service.dart';
import '../widgets/street_view_dialog.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_textfield.dart';
import '../widgets/custom_button.dart';
import 'potential_matches_page.dart';
import 'location_picker_page.dart';

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
  final _verificationQuestionController = TextEditingController();

  bool _isLost = true;
  String _category = 'Electronics';
  LatLng _selectedCoords = const LatLng(28.6139, 77.2090); // Default Delhi
  bool _loadingLocation = true;
  bool _submitting = false;
  bool _isAmberAlert = false;
  bool _reverseGeocoding = false;
  bool _isMapExpanded = false;

  GoogleMapController? _miniMapController;

  Future<void> _openFullScreenPicker() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => LocationPickerPage(
          initialCoords: _selectedCoords,
          initialAddress: _locDescController.text,
          title: _isLost ? 'Pinpoint Lost Location' : 'Pinpoint Found Location',
          confirmButtonText: 'Set Report Location',
          isLost: _isLost,
        ),
      ),
    );

    if (result != null && mounted) {
      final lat = (result['latitude'] as num).toDouble();
      final lng = (result['longitude'] as num).toDouble();
      final name = result['name'] as String?;
      final newCoords = LatLng(lat, lng);
      setState(() {
        _selectedCoords = newCoords;
        if (name != null && name.trim().isNotEmpty && name != 'Shared Spot' && name != 'Selected Location') {
          _locDescController.text = name.trim();
        }
      });
      _miniMapController?.animateCamera(CameraUpdate.newLatLngZoom(newCoords, 15.0));
    }
  }

  final List<String> _categories = [
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
    _fetchCurrentLocation();
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
    _verificationQuestionController.dispose();
    super.dispose();
  }

  Future<void> _reverseGeocode(LatLng coords) async {
    if (!mounted) return;
    setState(() => _reverseGeocoding = true);
    try {
      final address = await GoogleMapsService.reverseGeocode(
        coords.latitude,
        coords.longitude,
      );
      if (mounted && address.isNotEmpty && address != 'Selected Location') {
        setState(() {
          _locDescController.text = address;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _reverseGeocoding = false);
      }
    }
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
      _miniMapController?.animateCamera(CameraUpdate.newLatLngZoom(_selectedCoords, 14.0));
      _reverseGeocode(_selectedCoords);
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
      imageUrl: null,
      latitude: _selectedCoords.latitude,
      longitude: _selectedCoords.longitude,
      locationDescription: _locDescController.text.trim(),
      isLost: _isLost,
      category: _category,
      dateTime: DateTime.now(),
      reporterId: firebaseService.currentUserId!,
      reporterName: firebaseService.currentUser?.displayName ?? 'Anonymous',
      verificationQuestion: _verificationQuestionController.text.trim().isNotEmpty 
          ? _verificationQuestionController.text.trim() 
          : null,
      isAmberAlert: _category == 'Pets' && _isLost ? _isAmberAlert : false,
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
    _verificationQuestionController.clear();
    setState(() {
      _isLost = true;
      _category = 'Electronics';
      _isAmberAlert = false;
    });
  }

  static const Map<String, IconData> _categoryIcons = {
    'Electronics': Icons.phone_iphone_rounded,
    'Keys': Icons.vpn_key_rounded,
    'Wallets': Icons.account_balance_wallet_rounded,
    'Documents': Icons.badge_outlined,
    'Pets': Icons.pets_rounded,
    'Clothing': Icons.checkroom_rounded,
    'Others': Icons.category_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final activeColor = _isLost ? AppTheme.lostColor : AppTheme.foundColor;
    final activeGradient = _isLost ? AppTheme.lostGradient : AppTheme.foundGradient;

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header title with icon
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: activeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _isLost ? Icons.search_rounded : Icons.volunteer_activism_rounded,
                      color: activeColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isLost ? 'Report Lost Item' : 'Report Found Item',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                            letterSpacing: -0.3,
                          ),
                        ),
                        Text(
                          _isLost
                              ? 'Help our community find what you lost'
                              : 'Help return a found item to its rightful owner',
                          style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Segmented controls for Lost/Found type
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppTheme.cardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.border, width: 1),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _isLost = true),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            gradient: _isLost ? AppTheme.lostGradient : null,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: _isLost
                                ? [
                                    BoxShadow(
                                      color: AppTheme.lostColor.withValues(alpha: 0.35),
                                      blurRadius: 10,
                                      offset: const Offset(0, 3),
                                    )
                                  ]
                                : null,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.search_rounded,
                                size: 16,
                                color: _isLost ? Colors.white : AppTheme.textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'I LOST SOMETHING',
                                style: TextStyle(
                                  color: _isLost ? Colors.white : AppTheme.textSecondary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _isLost = false;
                          _isAmberAlert = false;
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            gradient: !_isLost ? AppTheme.foundGradient : null,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: !_isLost
                                ? [
                                    BoxShadow(
                                      color: AppTheme.foundColor.withValues(alpha: 0.35),
                                      blurRadius: 10,
                                      offset: const Offset(0, 3),
                                    )
                                  ]
                                : null,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.volunteer_activism_rounded,
                                size: 16,
                                color: !_isLost ? Colors.white : AppTheme.textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'I FOUND SOMETHING',
                                style: TextStyle(
                                  color: !_isLost ? Colors.white : AppTheme.textSecondary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Category Selector Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Item Category',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: activeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: activeColor.withValues(alpha: 0.3), width: 1),
                    ),
                    child: Text(
                      _category,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: activeColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Category Grid
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.84,
                ),
                itemCount: _categories.length,
                itemBuilder: (context, index) {
                  final cat = _categories[index];
                  final isSelected = _category == cat;
                  final icon = _categoryIcons[cat] ?? Icons.category_rounded;
                  final isPet = cat == 'Pets';

                  return InkWell(
                    onTap: () {
                      setState(() {
                        _category = cat;
                        if (!isPet) _isAmberAlert = false;
                      });
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? activeColor.withValues(alpha: 0.14)
                            : AppTheme.cardBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected ? activeColor : AppTheme.border,
                          width: isSelected ? 1.8 : 1,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: activeColor.withValues(alpha: 0.25),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                )
                              ]
                            : null,
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? activeColor.withValues(alpha: 0.2)
                                      : Colors.white.withValues(alpha: 0.05),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  icon,
                                  size: 18,
                                  color: isSelected ? activeColor : AppTheme.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    cat,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                      color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (isPet && _isLost)
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: AppTheme.lostColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),

              // Title field
              CustomTextField(
                controller: _titleController,
                label: 'Item Title',
                hint: 'e.g. Black Leather Wallet',
                prefixIcon: Icons.title_rounded,
                validator: (val) => val == null || val.isEmpty ? 'Title is required' : null,
              ),
              const SizedBox(height: 16),

              // Description field
              CustomTextField(
                controller: _descController,
                label: 'Description',
                hint: 'Describe details, brands, tags, unique marks...',
                prefixIcon: Icons.notes_rounded,
                maxLines: 3,
                validator: (val) => val == null || val.isEmpty ? 'Description is required' : null,
              ),
              const SizedBox(height: 16),

              // Location Description field
              CustomTextField(
                controller: _locDescController,
                label: 'Location Description',
                hint: _reverseGeocoding ? 'Detecting address from map...' : 'e.g. Near Metro Station exit gate',
                prefixIcon: Icons.place_outlined,
                suffixIcon: _reverseGeocoding
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: Padding(
                          padding: EdgeInsets.all(12.0),
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.secondary),
                        ),
                      )
                    : null,
                validator: (val) => val == null || val.isEmpty ? 'Location description is required' : null,
              ),
              const SizedBox(height: 16),

              // Verification Question field
              CustomTextField(
                controller: _verificationQuestionController,
                label: 'Ownership Verification Question (Optional)',
                hint: 'e.g. What color sticker is on the back?',
                prefixIcon: Icons.verified_user_outlined,
              ),
              const SizedBox(height: 18),

              // Amber Alert Card
              if (_category == 'Pets' && _isLost) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.lostColor.withValues(alpha: 0.08),
                    border: Border.all(color: AppTheme.lostColor.withValues(alpha: 0.35), width: 1.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: AppTheme.lostColor.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.notification_important_rounded,
                          color: AppTheme.lostColor,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Text(
                              'Trigger Local Amber Alert',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Instantly notifies nearby users in a 5 km radius',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 11,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Transform.scale(
                        scale: 0.85,
                        child: Switch(
                          value: _isAmberAlert,
                          activeThumbColor: AppTheme.lostColor,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          onChanged: (val) {
                            setState(() {
                              _isAmberAlert = val;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
              ],

              // Mini Map Picker Section
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.cardBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppTheme.border, width: 1),
                ),
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.map_rounded, size: 16, color: AppTheme.secondary),
                            SizedBox(width: 6),
                            Text(
                              'Pinpoint on Map',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Height expand/compact toggle
                            InkWell(
                              onTap: () {
                                setState(() {
                                  _isMapExpanded = !_isMapExpanded;
                                });
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppTheme.border),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _isMapExpanded ? Icons.unfold_less_rounded : Icons.unfold_more_rounded,
                                      size: 13,
                                      color: AppTheme.textSecondary,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      _isMapExpanded ? 'Compact' : 'Expand',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.textSecondary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            // Fullscreen interactive picker button
                            InkWell(
                              onTap: _openFullScreenPicker,
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: activeColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: activeColor.withValues(alpha: 0.35)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.open_in_full_rounded, size: 13, color: activeColor),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Full Map',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: activeColor,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            // Street View button
                            InkWell(
                              onTap: () {
                                StreetViewDialog.show(
                                  context,
                                  latitude: _selectedCoords.latitude,
                                  longitude: _selectedCoords.longitude,
                                  locationTitle: _locDescController.text.isNotEmpty
                                      ? _locDescController.text
                                      : 'Report Location',
                                );
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppTheme.secondary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppTheme.secondary.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Icon(Icons.streetview_rounded, size: 13, color: AppTheme.secondary),
                                    SizedBox(width: 4),
                                    Text(
                                      '360°',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.secondary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      height: _isMapExpanded ? 340 : 210,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.border, width: 1),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        children: [
                          GoogleMap(
                            gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                              Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
                            },
                            style: GoogleMapsService.darkMapStyle,
                            initialCameraPosition: CameraPosition(
                              target: _selectedCoords,
                              zoom: 14.0,
                            ),
                            onMapCreated: (controller) {
                              _miniMapController = controller;
                            },
                            markers: {
                              Marker(
                                markerId: const MarkerId('report_pin'),
                                position: _selectedCoords,
                                icon: BitmapDescriptor.defaultMarkerWithHue(
                                  _isLost ? BitmapDescriptor.hueRed : BitmapDescriptor.hueGreen,
                                ),
                                draggable: true,
                                onDragEnd: (point) {
                                  setState(() {
                                    _selectedCoords = point;
                                  });
                                  _reverseGeocode(point);
                                },
                              ),
                            },
                            onTap: (point) {
                              setState(() {
                                _selectedCoords = point;
                              });
                              _reverseGeocode(point);
                            },
                            myLocationEnabled: true,
                            myLocationButtonEnabled: false,
                            zoomControlsEnabled: false,
                            mapToolbarEnabled: false,
                            compassEnabled: true,
                          ),
                          if (_loadingLocation)
                            Container(
                              color: Colors.black.withValues(alpha: 0.5),
                              child: const Center(
                                child: CircularProgressIndicator(color: AppTheme.primary),
                              ),
                            ),

                          // Top-left gesture instruction badge
                          Positioned(
                            top: 8,
                            left: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.darkBg.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppTheme.border.withValues(alpha: 0.6)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.touch_app_rounded, size: 12, color: AppTheme.secondary),
                                  SizedBox(width: 4),
                                  Text(
                                    'Pinch or use +/- to zoom',
                                    style: TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Right-side floating vertical zoom & map controls cluster
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppTheme.cardBg.withValues(alpha: 0.95),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppTheme.border, width: 1.2),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.35),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Zoom In (+)
                                  Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                                      onTap: () {
                                        _miniMapController?.animateCamera(CameraUpdate.zoomIn());
                                      },
                                      child: const Tooltip(
                                        message: 'Zoom In',
                                        child: Padding(
                                          padding: EdgeInsets.all(7.0),
                                          child: Icon(Icons.add_rounded, size: 18, color: AppTheme.textPrimary),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Container(width: 24, height: 1, color: AppTheme.border),
                                  // Zoom Out (-)
                                  Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.zero,
                                      onTap: () {
                                        _miniMapController?.animateCamera(CameraUpdate.zoomOut());
                                      },
                                      child: const Tooltip(
                                        message: 'Zoom Out',
                                        child: Padding(
                                          padding: EdgeInsets.all(7.0),
                                          child: Icon(Icons.remove_rounded, size: 18, color: AppTheme.textPrimary),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Container(width: 24, height: 1, color: AppTheme.border),
                                  // Focus on Pin
                                  Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.zero,
                                      onTap: () {
                                        _miniMapController?.animateCamera(
                                          CameraUpdate.newLatLngZoom(_selectedCoords, 16.0),
                                        );
                                      },
                                      child: const Tooltip(
                                        message: 'Focus on Pin',
                                        child: Padding(
                                          padding: EdgeInsets.all(7.0),
                                          child: Icon(Icons.filter_center_focus_rounded, size: 17, color: AppTheme.secondary),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Container(width: 24, height: 1, color: AppTheme.border),
                                  // GPS Current Location
                                  Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.zero,
                                      onTap: _fetchCurrentLocation,
                                      child: const Tooltip(
                                        message: 'Current Location',
                                        child: Padding(
                                          padding: EdgeInsets.all(7.0),
                                          child: Icon(Icons.my_location_rounded, size: 17, color: AppTheme.primary),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Container(width: 24, height: 1, color: AppTheme.border),
                                  // Fullscreen Map launcher
                                  Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
                                      onTap: _openFullScreenPicker,
                                      child: Tooltip(
                                        message: 'Open Fullscreen Map',
                                        child: Padding(
                                          padding: const EdgeInsets.all(7.0),
                                          child: Icon(Icons.open_in_full_rounded, size: 16, color: activeColor),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.location_on_rounded, size: 13, color: AppTheme.textMuted),
                            const SizedBox(width: 4),
                            Text(
                              '${_selectedCoords.latitude.toStringAsFixed(4)}, ${_selectedCoords.longitude.toStringAsFixed(4)}',
                              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                        InkWell(
                          onTap: _openFullScreenPicker,
                          child: Row(
                            children: [
                              Text(
                                'Precision search & picker',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: activeColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 2),
                              Icon(Icons.chevron_right_rounded, size: 14, color: activeColor),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              CustomButton(
                text: _isLost ? 'Submit Lost Report' : 'Submit Found Report',
                icon: _isLost ? Icons.search_rounded : Icons.check_circle_outline_rounded,
                gradient: activeGradient,
                isLoading: _submitting,
                onPressed: _submit,
              ),
              const SizedBox(height: 36),
            ],
          ),
        ),
      ),
    );
  }
}

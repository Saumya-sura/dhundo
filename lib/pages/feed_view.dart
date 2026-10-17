import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/item_model.dart';
import '../services/firebase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/street_view_dialog.dart';
import 'chat_page.dart';

class FeedView extends StatefulWidget {
  const FeedView({super.key});

  @override
  State<FeedView> createState() => _FeedViewState();
}

class _FeedViewState extends State<FeedView> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedCategory = 'All';
  String _selectedType = 'All'; // 'All', 'Lost', 'Found'
  bool _sortByLatest = true;

  final List<Map<String, dynamic>> _categoryData = [
    {'name': 'All', 'icon': Icons.grid_view_rounded},
    {'name': 'Electronics', 'icon': Icons.devices_rounded},
    {'name': 'Keys', 'icon': Icons.vpn_key_rounded},
    {'name': 'Wallets', 'icon': Icons.account_balance_wallet_rounded},
    {'name': 'Documents', 'icon': Icons.description_rounded},
    {'name': 'Pets', 'icon': Icons.pets_rounded},
    {'name': 'Clothing', 'icon': Icons.checkroom_rounded},
    {'name': 'Others', 'icon': Icons.category_rounded},
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase().trim();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _navigateToChat(ItemModel item, FirebaseService firebaseService, {bool isDemoFinder = false, String? initialMessage}) async {
    final currentUserId = firebaseService.currentUserId ?? '';
    final isOwnPost = item.reporterId == currentUserId;

    if (isOwnPost && !isDemoFinder) {
      // User tapped their own post - offer demo mode or info
      final shouldSimulate = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          backgroundColor: AppTheme.cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppTheme.border, width: 1.2),
          ),
          title: Row(
            children: const [
              Icon(Icons.person_pin_circle_rounded, color: AppTheme.secondary),
              SizedBox(width: 8),
              Text('Your Report', style: TextStyle(fontSize: 17, color: AppTheme.textPrimary)),
            ],
          ),
          content: Text(
            'This report was created by you. Would you like to start a simulated test chat as a finder/claimant to test the messaging & handover flow?',
            style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Close', style: TextStyle(color: AppTheme.textMuted)),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(dialogCtx, true),
              icon: const Icon(Icons.forum_rounded, size: 16),
              label: const Text('Test Chat Flow'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      );

      if (shouldSimulate != true) return;
    }

    if (!mounted) return;

    // Ownership Verification Check (only if not simulating demo on own post)
    if (!isOwnPost && item.verificationQuestion != null && item.verificationQuestion!.trim().isNotEmpty) {
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
              Icon(Icons.vpn_key_rounded, color: Color(0xFFFBBF24)),
              SizedBox(width: 8),
              Text('Verification Required', style: TextStyle(fontSize: 17, color: AppTheme.textPrimary)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'The reporter set an ownership verification question to protect this item:',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.darkBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                ),
                child: Text(
                  item.verificationQuestion!,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFBBF24),
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: answerController,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13.5),
                decoration: InputDecoration(
                  hintText: 'Type your answer to verify...',
                  hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  filled: true,
                  fillColor: AppTheme.darkBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppTheme.border),
                  ),
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
                    const SnackBar(content: Text('Please enter an answer to proceed.')),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Submit & Chat'),
            ),
          ],
        ),
      );

      if (hasAnswered != true) return;

      try {
        final currentUserName = firebaseService.currentUser?.displayName ?? 'Samaritan';
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
      final currentUserName = isOwnPost && isDemoFinder
          ? 'Helpful Neighbor'
          : (firebaseService.currentUser?.displayName ?? 'Anonymous');
      final simulatedFinderId = isOwnPost && isDemoFinder ? 'demo_finder_${item.id.substring(0, 5)}' : (firebaseService.currentUserId ?? 'user');

      final chatRoom = await firebaseService.getOrCreateChatRoom(
        itemId: item.id,
        itemTitle: item.title,
        itemIsLost: item.isLost,
        ownerId: item.isLost ? item.reporterId : (isOwnPost && isDemoFinder ? simulatedFinderId : firebaseService.currentUserId!),
        ownerName: item.isLost ? item.reporterName : currentUserName,
        finderId: item.isLost ? (isOwnPost && isDemoFinder ? simulatedFinderId : firebaseService.currentUserId!) : item.reporterId,
        finderName: item.isLost ? currentUserName : item.reporterName,
      );

      if (initialMessage != null && initialMessage.isNotEmpty) {
        await firebaseService.sendMessage(chatRoom.id, initialMessage, currentUserName);
      }

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
      backgroundColor: AppTheme.darkBg,
      body: Column(
        children: [
          // Cyber Search & Filter Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top row title and live indicator
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: AppTheme.secondary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.rss_feed_rounded,
                        color: AppTheme.secondary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'COMMUNITY FEED',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.textPrimary,
                              letterSpacing: 0.4,
                            ),
                          ),
                          Text(
                            'Real-time reports across your neighborhood',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Quick Sort Button
                    InkWell(
                      onTap: () => setState(() => _sortByLatest = !_sortByLatest),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.cardBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.border, width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _sortByLatest ? Icons.schedule_rounded : Icons.history_rounded,
                              size: 14,
                              color: AppTheme.secondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _sortByLatest ? 'Newest' : 'Oldest',
                              style: const TextStyle(
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
                const SizedBox(height: 12),

                // Search Box
                Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.cardBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border, width: 1),
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13.5),
                    decoration: InputDecoration(
                      hintText: 'Search lost phones, keys, wallets, pets...',
                      hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 12.5),
                      prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textSecondary, size: 18),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 16, color: AppTheme.textMuted),
                              onPressed: () => _searchController.clear(),
                            )
                          : null,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Type selector Segmented Buttons: All | Lost | Found
                Row(
                  children: [
                    _buildTypePill('All', Icons.grid_view_rounded, null),
                    const SizedBox(width: 8),
                    _buildTypePill('Lost', Icons.search_rounded, AppTheme.lostColor),
                    const SizedBox(width: 8),
                    _buildTypePill('Found', Icons.check_circle_outline_rounded, AppTheme.foundColor),
                  ],
                ),
              ],
            ),
          ),

          // Category scrolling chips row with icons
          Container(
            height: 40,
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _categoryData.length,
              itemBuilder: (context, index) {
                final cat = _categoryData[index];
                final String name = cat['name'] as String;
                final IconData icon = cat['icon'] as IconData;
                final isSelected = _selectedCategory == name;

                return Padding(
                  padding: const EdgeInsets.only(right: 6.0),
                  child: InkWell(
                    onTap: () => setState(() => _selectedCategory = name),
                    borderRadius: BorderRadius.circular(20),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.primary.withValues(alpha: 0.2)
                            : AppTheme.cardBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected ? AppTheme.primary : AppTheme.border,
                          width: isSelected ? 1.2 : 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            icon,
                            size: 14,
                            color: isSelected ? AppTheme.primaryAccent : AppTheme.textSecondary,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            name,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              color: isSelected ? Colors.white : AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Items Grid/List View Builder
          Expanded(
            child: StreamBuilder<List<ItemModel>>(
              stream: firebaseService.getItems(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: AppTheme.secondary));
                }

                List<ItemModel> allItems = snapshot.data ?? [];

                // Filter out resolved posts
                allItems = allItems.where((i) => i.status == 'active').toList();

                // Extract active Amber Alerts
                final amberAlerts = allItems.where((i) => i.isAmberAlert).toList();

                // Apply Filters to main feed list
                List<ItemModel> filteredItems = List.from(allItems);
                if (_selectedCategory != 'All') {
                  filteredItems = filteredItems.where((i) => i.category == _selectedCategory).toList();
                }

                if (_selectedType == 'Lost') {
                  filteredItems = filteredItems.where((i) => i.isLost).toList();
                } else if (_selectedType == 'Found') {
                  filteredItems = filteredItems.where((i) => !i.isLost).toList();
                }

                if (_searchQuery.isNotEmpty) {
                  filteredItems = filteredItems.where((i) =>
                      i.title.toLowerCase().contains(_searchQuery) ||
                      i.description.toLowerCase().contains(_searchQuery) ||
                      i.locationDescription.toLowerCase().contains(_searchQuery)).toList();
                }

                // Sort Items
                if (!_sortByLatest) {
                  filteredItems = filteredItems.reversed.toList();
                }

                return Column(
                  children: [
                    // Dynamic Amber Alerts Slider Banner
                    if (amberAlerts.isNotEmpty) ...[
                      Container(
                        height: 98,
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: amberAlerts.length,
                          itemBuilder: (context, index) {
                            final alert = amberAlerts[index];
                            return Container(
                              width: MediaQuery.of(context).size.width * 0.85,
                              margin: const EdgeInsets.only(right: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppTheme.lostColor.withValues(alpha: 0.22),
                                    AppTheme.cardBg,
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                border: Border.all(
                                  color: AppTheme.lostColor.withValues(alpha: 0.5),
                                  width: 1.2,
                                ),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.lostColor.withValues(alpha: 0.15),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  const PulsingWarningIcon(),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Row(
                                          children: const [
                                            Text(
                                              '🚨 NEIGHBORHOOD AMBER ALERT',
                                              style: TextStyle(
                                                color: AppTheme.lostColor,
                                                fontWeight: FontWeight.w900,
                                                fontSize: 10,
                                                letterSpacing: 0.8,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          alert.title,
                                          style: const TextStyle(
                                            color: AppTheme.textPrimary,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13.5,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          alert.locationDescription,
                                          style: const TextStyle(
                                            color: AppTheme.textMuted,
                                            fontSize: 11,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    onPressed: () => _navigateToChat(alert, firebaseService),
                                    icon: const Icon(Icons.chat_bubble_outline_rounded, size: 14),
                                    label: const Text('Help / Chat'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.lostColor,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],

                    Expanded(
                      child: filteredItems.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32.0),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.search_off_rounded,
                                      size: 52,
                                      color: AppTheme.textMuted.withValues(alpha: 0.5),
                                    ),
                                    const SizedBox(height: 14),
                                    const Text(
                                      'No Reports Found',
                                      style: TextStyle(
                                        color: AppTheme.textPrimary,
                                        fontSize: 17,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _searchQuery.isNotEmpty
                                          ? 'No reports matching "$_searchQuery" in category "$_selectedCategory".'
                                          : 'Try selecting a different filter or submit a new report.',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: AppTheme.textMuted,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 2, 16, 24),
                              itemCount: filteredItems.length,
                              itemBuilder: (context, index) {
                                final item = filteredItems[index];
                                final isOwner = item.reporterId == firebaseService.currentUserId;
                                final dateStr = _formatDate(item.dateTime);
                                final color = item.isLost ? AppTheme.lostColor : AppTheme.foundColor;
                                final hasVerification = item.verificationQuestion != null && item.verificationQuestion!.trim().isNotEmpty;

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 14),
                                  decoration: BoxDecoration(
                                    color: AppTheme.cardBg,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: item.isAmberAlert
                                          ? AppTheme.lostColor.withValues(alpha: 0.5)
                                          : AppTheme.border,
                                      width: item.isAmberAlert ? 1.4 : 1,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.25),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      if (item.imageUrl != null)
                                        Image.network(
                                          item.imageUrl!,
                                          height: 180,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) => Container(
                                            height: 100,
                                            color: AppTheme.darkBg,
                                            child: const Icon(Icons.broken_image, size: 40, color: AppTheme.textMuted),
                                          ),
                                        ),
                                      Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            // Tags Row
                                            Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                                                  decoration: BoxDecoration(
                                                    color: color.withValues(alpha: 0.15),
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: Border.all(color: color.withValues(alpha: 0.6), width: 0.8),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        item.isLost ? Icons.search_rounded : Icons.check_circle_outline_rounded,
                                                        size: 11,
                                                        color: color,
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        item.isLost ? 'LOST' : 'FOUND',
                                                        style: TextStyle(
                                                          color: color,
                                                          fontSize: 10.5,
                                                          fontWeight: FontWeight.w900,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                                                  decoration: BoxDecoration(
                                                    color: AppTheme.secondary.withValues(alpha: 0.12),
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: Border.all(color: AppTheme.secondary.withValues(alpha: 0.3), width: 0.8),
                                                  ),
                                                  child: Text(
                                                    item.category,
                                                    style: const TextStyle(
                                                      color: AppTheme.secondary,
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                                const Spacer(),
                                                Text(
                                                  dateStr,
                                                  style: const TextStyle(
                                                    color: AppTheme.textMuted,
                                                    fontSize: 11.5,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 10),

                                            // Title
                                            Text(
                                              item.title,
                                              style: const TextStyle(
                                                fontSize: 16.5,
                                                fontWeight: FontWeight.bold,
                                                color: AppTheme.textPrimary,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 5),

                                            // Description
                                            Text(
                                              item.description,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: AppTheme.textSecondary,
                                                fontSize: 13,
                                                height: 1.35,
                                              ),
                                            ),
                                            const SizedBox(height: 10),

                                            // Location & Street View row
                                            Row(
                                              children: [
                                                const Icon(Icons.place_rounded, size: 14, color: AppTheme.secondary),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    item.locationDescription,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      color: AppTheme.textMuted,
                                                    ),
                                                  ),
                                                ),
                                                InkWell(
                                                  onTap: () {
                                                    StreetViewDialog.show(
                                                      context,
                                                      latitude: item.latitude,
                                                      longitude: item.longitude,
                                                      locationTitle: item.locationDescription,
                                                    );
                                                  },
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color: AppTheme.secondary.withValues(alpha: 0.1),
                                                      borderRadius: BorderRadius.circular(6),
                                                      border: Border.all(color: AppTheme.secondary.withValues(alpha: 0.3), width: 0.8),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: const [
                                                        Icon(Icons.streetview_rounded, size: 11, color: AppTheme.secondary),
                                                        SizedBox(width: 3),
                                                        Text(
                                                          '360° View',
                                                          style: TextStyle(
                                                            fontSize: 10,
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

                                            // Verification Badge if present
                                            if (hasVerification) ...[
                                              const SizedBox(height: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.35), width: 0.8),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: const [
                                                    Icon(Icons.vpn_key_rounded, size: 12, color: Color(0xFFFBBF24)),
                                                    SizedBox(width: 4),
                                                    Text(
                                                      'Ownership Verification Required',
                                                      style: TextStyle(
                                                        color: Color(0xFFFBBF24),
                                                        fontSize: 10.5,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],

                                            const Divider(color: AppTheme.border, height: 22),

                                            // Reporter Profile & Action Row
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                // User metadata
                                                FutureBuilder<Map<String, dynamic>?>(
                                                  future: firebaseService.getUserProfile(item.reporterId),
                                                  builder: (context, userSnapshot) {
                                                    final userData = userSnapshot.data;
                                                    final ratingSum = userData?['ratingSum'] as num?;
                                                    final ratingCount = userData?['ratingCount'] as int? ?? 0;
                                                    final averageRating = ratingCount > 0 ? (ratingSum!.toDouble() / ratingCount) : null;
                                                    final badges = List<String>.from(userData?['badges'] ?? []);

                                                    return Expanded(
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Row(
                                                            children: [
                                                              Flexible(
                                                                child: Text(
                                                                  isOwner ? 'You (Reporter)' : 'By ${item.reporterName}',
                                                                  style: TextStyle(
                                                                    fontSize: 12.5,
                                                                    color: isOwner ? AppTheme.secondary : AppTheme.textSecondary,
                                                                    fontWeight: FontWeight.bold,
                                                                  ),
                                                                  maxLines: 1,
                                                                  overflow: TextOverflow.ellipsis,
                                                                ),
                                                              ),
                                                              if (averageRating != null) ...[
                                                                const SizedBox(width: 6),
                                                                const Icon(Icons.star_rounded, color: Colors.amberAccent, size: 13),
                                                                const SizedBox(width: 2),
                                                                Text(
                                                                  averageRating.toStringAsFixed(1),
                                                                  style: const TextStyle(
                                                                    fontSize: 11,
                                                                    color: Colors.amberAccent,
                                                                    fontWeight: FontWeight.bold,
                                                                  ),
                                                                ),
                                                              ],
                                                            ],
                                                          ),
                                                          if (badges.isNotEmpty) ...[
                                                            const SizedBox(height: 3),
                                                            Wrap(
                                                              spacing: 4,
                                                              children: badges.take(2).map((badge) {
                                                                return Container(
                                                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                                  decoration: BoxDecoration(
                                                                    color: AppTheme.primary.withValues(alpha: 0.12),
                                                                    border: Border.all(
                                                                      color: AppTheme.primaryAccent.withValues(alpha: 0.4),
                                                                      width: 0.6,
                                                                    ),
                                                                    borderRadius: BorderRadius.circular(4),
                                                                  ),
                                                                  child: Text(
                                                                    badge,
                                                                    style: const TextStyle(
                                                                      fontSize: 8.5,
                                                                      color: AppTheme.primaryAccent,
                                                                      fontWeight: FontWeight.bold,
                                                                    ),
                                                                  ),
                                                                );
                                                              }).toList(),
                                                            ),
                                                          ],
                                                        ],
                                                      ),
                                                    );
                                                  },
                                                ),
                                                const SizedBox(width: 8),

                                                // Chat Action Buttons
                                                Row(
                                                  children: [
                                                    if (isOwner) ...[
                                                      // Simulate test chat button for own post
                                                      OutlinedButton.icon(
                                                        onPressed: () => _navigateToChat(item, firebaseService, isDemoFinder: true),
                                                        icon: const Icon(Icons.forum_outlined, size: 14),
                                                        label: const Text('Test Chat', style: TextStyle(fontSize: 11)),
                                                        style: OutlinedButton.styleFrom(
                                                          foregroundColor: AppTheme.secondary,
                                                          side: BorderSide(color: AppTheme.secondary.withValues(alpha: 0.4)),
                                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                        ),
                                                      ),
                                                    ] else ...[
                                                      // Quick inquire button
                                                      IconButton(
                                                        onPressed: () => _navigateToChat(
                                                          item,
                                                          firebaseService,
                                                          initialMessage: 'Hi, I saw your report for "${item.title}". Is this still available?',
                                                        ),
                                                        icon: const Icon(Icons.quickreply_rounded, color: AppTheme.secondary, size: 18),
                                                        tooltip: 'Quick Inquire',
                                                        style: IconButton.styleFrom(
                                                          backgroundColor: AppTheme.secondary.withValues(alpha: 0.1),
                                                          padding: const EdgeInsets.all(8),
                                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 6),
                                                      // Primary Chat CTA
                                                      ElevatedButton.icon(
                                                        onPressed: () => _navigateToChat(item, firebaseService),
                                                        icon: Icon(
                                                          hasVerification ? Icons.vpn_key_rounded : Icons.chat_rounded,
                                                          size: 13,
                                                        ),
                                                        label: Text(
                                                          hasVerification
                                                              ? 'Verify & Chat'
                                                              : (item.isLost ? 'I Found It!' : 'Claim / Chat'),
                                                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                                                        ),
                                                        style: ElevatedButton.styleFrom(
                                                          backgroundColor: hasVerification ? const Color(0xFFD97706) : AppTheme.primary,
                                                          foregroundColor: Colors.white,
                                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                          shape: RoundedRectangleBorder(
                                                            borderRadius: BorderRadius.circular(10),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypePill(String label, IconData icon, Color? color) {
    final isSelected = _selectedType == label;
    final activeColor = color ?? AppTheme.primary;

    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedType = label),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? activeColor.withValues(alpha: 0.2)
                : AppTheme.cardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? activeColor : AppTheme.border,
              width: isSelected ? 1.2 : 0.8,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 13,
                color: isSelected ? activeColor : AppTheme.textSecondary,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? Colors.white : AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 2) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays == 0 && now.day == dateTime.day) {
      return 'Today, ${DateFormat('hh:mm a').format(dateTime)}';
    } else if (difference.inDays == 1 || (difference.inDays == 0 && now.day != dateTime.day)) {
      return 'Yesterday, ${DateFormat('hh:mm a').format(dateTime)}';
    } else {
      return DateFormat('MMM dd, yyyy').format(dateTime);
    }
  }
}

class PulsingWarningIcon extends StatefulWidget {
  const PulsingWarningIcon({super.key});

  @override
  State<PulsingWarningIcon> createState() => _PulsingWarningIconState();
}

class _PulsingWarningIconState extends State<PulsingWarningIcon> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.85, end: 1.15).animate(
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
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppTheme.lostColor.withValues(alpha: 0.2),
        ),
        child: const Icon(Icons.warning_rounded, color: AppTheme.lostColor, size: 22),
      ),
    );
  }
}

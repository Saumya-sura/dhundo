import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/item_model.dart';
import '../services/firebase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_textfield.dart';
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
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
      body: Column(
        children: [
          // Filter & Search Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              children: [
                CustomTextField(
                  controller: _searchController,
                  label: 'Search lost & found items',
                  prefixIcon: Icons.search_rounded,
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, color: AppTheme.textMuted),
                          onPressed: () => _searchController.clear(),
                        )
                      : null,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    // Type selector (All, Lost, Found)
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.cardBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.border, width: 1),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedType,
                            dropdownColor: AppTheme.cardBg,
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.textSecondary),
                            isExpanded: true,
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _selectedType = val;
                                });
                              }
                            },
                            items: const [
                              DropdownMenuItem(value: 'All', child: Text('All Types')),
                              DropdownMenuItem(value: 'Lost', child: Text('Lost Only')),
                              DropdownMenuItem(value: 'Found', child: Text('Found Only')),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Sorting button
                    IconButton(
                      icon: Icon(
                        _sortByLatest ? Icons.swap_vert_rounded : Icons.swap_vertical_circle_rounded,
                        color: AppTheme.primaryAccent,
                      ),
                      tooltip: _sortByLatest ? 'Sorting: Newest' : 'Sorting: Oldest',
                      onPressed: () {
                        setState(() {
                          _sortByLatest = !_sortByLatest;
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Category scrolling chips row
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final cat = _categories[index];
                final isSelected = _selectedCategory == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 6.0),
                  child: ChoiceChip(
                    label: Text(cat, style: const TextStyle(fontSize: 12)),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _selectedCategory = cat;
                      });
                    },
                    backgroundColor: AppTheme.cardBg,
                    selectedColor: AppTheme.primary,
                    checkmarkColor: Colors.white,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : AppTheme.textSecondary,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                      side: BorderSide(
                        color: isSelected ? AppTheme.primary : AppTheme.border,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),

          // Items Grid/List View Builder
          Expanded(
            child: StreamBuilder<List<ItemModel>>(
              stream: firebaseService.getItems(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
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
                        height: 96,
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: amberAlerts.length,
                          itemBuilder: (context, index) {
                            final alert = amberAlerts[index];
                            return Container(
                              width: MediaQuery.of(context).size.width * 0.82,
                              margin: const EdgeInsets.only(right: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [AppTheme.lostColor.withOpacity(0.18), AppTheme.cardBg],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                border: Border.all(color: AppTheme.lostColor.withOpacity(0.4), width: 1.2),
                                borderRadius: BorderRadius.circular(16),
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
                                        const Text(
                                          '🚨 NEIGHBORHOOD AMBER ALERT',
                                          style: TextStyle(
                                            color: AppTheme.lostColor,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 9.5,
                                            letterSpacing: 0.8,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          alert.title,
                                          style: const TextStyle(
                                            color: AppTheme.textPrimary,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          alert.locationDescription,
                                          style: const TextStyle(
                                            color: AppTheme.textMuted,
                                            fontSize: 10.5,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    onPressed: () => _navigateToChat(alert, firebaseService),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.lostColor,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    child: const Text(
                                      'Help',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
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
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.search_off_rounded, size: 50, color: AppTheme.textMuted.withOpacity(0.5)),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'No reports found',
                                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 16),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              itemCount: filteredItems.length,
                              itemBuilder: (context, index) {
                                final item = filteredItems[index];
                                final dateStr = DateFormat('MMM dd, yyyy').format(item.dateTime);
                                final color = item.isLost ? AppTheme.lostColor : AppTheme.foundColor;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
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
                                height: 120,
                                color: AppTheme.darkBg,
                                child: const Icon(Icons.broken_image, size: 40),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: color.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: color, width: 0.8),
                                      ),
                                      child: Text(
                                        item.isLost ? 'LOST' : 'FOUND',
                                        style: TextStyle(
                                          color: color,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      item.category,
                                      style: const TextStyle(
                                        color: AppTheme.secondary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      dateStr,
                                      style: const TextStyle(
                                        color: AppTheme.textMuted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  item.title,
                                  style: Theme.of(context).textTheme.titleLarge,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  item.description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    const Icon(Icons.location_on_rounded, size: 14, color: AppTheme.textMuted),
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
                                  ],
                                ),
                                const Divider(color: AppTheme.border, height: 24),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
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
                                                      'By ${item.reporterName}',
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        color: AppTheme.textSecondary,
                                                        fontWeight: FontWeight.w600,
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
                                                        fontSize: 11.5,
                                                        color: Colors.amberAccent,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              if (badges.isNotEmpty) ...[
                                                const SizedBox(height: 4),
                                                Wrap(
                                                  spacing: 4,
                                                  runSpacing: 4,
                                                  children: badges.take(2).map((badge) {
                                                    return Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                      decoration: BoxDecoration(
                                                        color: AppTheme.primary.withOpacity(0.12),
                                                        border: Border.all(color: AppTheme.primaryAccent.withOpacity(0.5), width: 0.6),
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: Text(
                                                        badge,
                                                        style: const TextStyle(
                                                          fontSize: 8,
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
                                    TextButton.icon(
                                      onPressed: () => _navigateToChat(item, firebaseService),
                                      icon: Icon(
                                        item.reporterId == firebaseService.currentUserId
                                            ? Icons.check_circle_outline
                                            : Icons.chat_rounded,
                                        size: 16,
                                      ),
                                      label: Text(
                                        item.reporterId == firebaseService.currentUserId
                                            ? 'My Post'
                                            : 'Chat',
                                      ),
                                      style: TextButton.styleFrom(
                                        foregroundColor: AppTheme.primaryAccent,
                                      ),
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
          color: AppTheme.lostColor.withOpacity(0.2),
        ),
        child: const Icon(Icons.warning_rounded, color: AppTheme.lostColor, size: 22),
      ),
    );
  }
}

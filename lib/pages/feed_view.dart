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

                List<ItemModel> items = snapshot.data ?? [];

                // Filter out resolved posts
                items = items.where((i) => i.status == 'active').toList();

                // Apply Filters
                if (_selectedCategory != 'All') {
                  items = items.where((i) => i.category == _selectedCategory).toList();
                }

                if (_selectedType == 'Lost') {
                  items = items.where((i) => i.isLost).toList();
                } else if (_selectedType == 'Found') {
                  items = items.where((i) => !i.isLost).toList();
                }

                if (_searchQuery.isNotEmpty) {
                  items = items.where((i) =>
                      i.title.toLowerCase().contains(_searchQuery) ||
                      i.description.toLowerCase().contains(_searchQuery) ||
                      i.locationDescription.toLowerCase().contains(_searchQuery)).toList();
                }

                // Sort Items
                if (!_sortByLatest) {
                  items = items.reversed.toList();
                }

                if (items.isEmpty) {
                  return Center(
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
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
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
                                    Text(
                                      'Reported by: ${item.reporterName}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textSecondary,
                                        fontWeight: FontWeight.w500,
                                      ),
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
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

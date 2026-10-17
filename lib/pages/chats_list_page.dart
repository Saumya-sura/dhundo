import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/chat_model.dart';
import '../models/item_model.dart';
import '../services/firebase_service.dart';
import '../theme/app_theme.dart';
import 'chat_page.dart';

class ChatsListPage extends StatefulWidget {
  const ChatsListPage({super.key});

  @override
  State<ChatsListPage> createState() => _ChatsListPageState();
}

class _ChatsListPageState extends State<ChatsListPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _filter = 'All'; // 'All', 'Lost', 'Found'

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final firebaseService = Provider.of<FirebaseService>(context);

    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      body: StreamBuilder<List<ChatRoomModel>>(
        stream: firebaseService.getUserChatRooms(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.secondary),
            );
          }

          final allRooms = snapshot.data ?? [];

          // Apply filters
          final filteredRooms = allRooms.where((room) {
            final isOwner = room.ownerId == firebaseService.currentUserId;
            final otherPartyName = isOwner ? room.finderName : room.ownerName;

            // Search filter
            final matchesSearch = _searchQuery.isEmpty ||
                otherPartyName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                room.itemTitle.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                room.lastMessage.toLowerCase().contains(_searchQuery.toLowerCase());

            // Status filter
            final matchesStatus = _filter == 'All' ||
                (_filter == 'Lost' && room.itemIsLost) ||
                (_filter == 'Found' && !room.itemIsLost);

            return matchesSearch && matchesStatus;
          }).toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Section
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.secondary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.forum_rounded,
                        color: AppTheme.secondary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Active Handovers & Chats',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                              letterSpacing: -0.3,
                            ),
                          ),
                          Text(
                            'Real-time coordination with finders & owners',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    InkWell(
                      onTap: () => _showStartChatSheet(context, firebaseService),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppTheme.primary.withValues(alpha: 0.4),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.add_comment_rounded, size: 14, color: AppTheme.primaryAccent),
                            SizedBox(width: 4),
                            Text(
                              'New Chat',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryAccent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (allRooms.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.cardBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppTheme.secondary.withValues(alpha: 0.35),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          '${allRooms.length}',
                          style: const TextStyle(
                            color: AppTheme.secondary,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Search Box
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.cardBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border, width: 1),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val.trim()),
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13.5),
                    decoration: InputDecoration(
                      hintText: 'Search chats, items, or names...',
                      hintStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                      prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textSecondary, size: 18),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 16, color: AppTheme.textMuted),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ),

              // Filter Chips Row
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                child: Row(
                  children: [
                    _buildFilterChip('All', allRooms.length),
                    const SizedBox(width: 8),
                    _buildFilterChip('Lost', allRooms.where((r) => r.itemIsLost).length,
                        color: AppTheme.lostColor),
                    const SizedBox(width: 8),
                    _buildFilterChip('Found', allRooms.where((r) => !r.itemIsLost).length,
                        color: AppTheme.foundColor),
                  ],
                ),
              ),

              // Chat Rooms List
              Expanded(
                child: filteredRooms.isEmpty
                    ? _buildEmptyState(allRooms.isEmpty)
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: filteredRooms.length,
                        itemBuilder: (context, index) {
                          final room = filteredRooms[index];
                          final isOwner = room.ownerId == firebaseService.currentUserId;
                          final otherPartyName = isOwner ? room.finderName : room.ownerName;
                          final dateStr = _formatTimestamp(room.lastMessageTime);
                          final tagColor = room.itemIsLost ? AppTheme.lostColor : AppTheme.foundColor;
                          final isLiveSharing = room.liveLocations != null && room.liveLocations!.isNotEmpty;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10.0),
                            child: Material(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(16),
                              child: InkWell(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ChatPage(chatRoom: room),
                                    ),
                                  );
                                },
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: AppTheme.cardBg,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isLiveSharing
                                          ? AppTheme.secondary.withValues(alpha: 0.4)
                                          : AppTheme.border,
                                      width: isLiveSharing ? 1.2 : 1,
                                    ),
                                    boxShadow: isLiveSharing
                                        ? [
                                            BoxShadow(
                                              color: AppTheme.secondary.withValues(alpha: 0.12),
                                              blurRadius: 10,
                                              offset: const Offset(0, 3),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      // Avatar with status beacon
                                      Stack(
                                        children: [
                                          Container(
                                            width: 46,
                                            height: 46,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              gradient: LinearGradient(
                                                colors: [
                                                  AppTheme.primary.withValues(alpha: 0.3),
                                                  AppTheme.secondary.withValues(alpha: 0.2),
                                                ],
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              ),
                                              border: Border.all(
                                                color: AppTheme.primary.withValues(alpha: 0.4),
                                                width: 1.2,
                                              ),
                                            ),
                                            child: Center(
                                              child: Text(
                                                otherPartyName.isNotEmpty
                                                    ? otherPartyName[0].toUpperCase()
                                                    : 'U',
                                                style: const TextStyle(
                                                  color: AppTheme.textPrimary,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 18,
                                                ),
                                              ),
                                            ),
                                          ),
                                          Positioned(
                                            bottom: 1,
                                            right: 1,
                                            child: Container(
                                              width: 11,
                                              height: 11,
                                              decoration: BoxDecoration(
                                                color: AppTheme.foundColor,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: AppTheme.cardBg,
                                                  width: 2,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(width: 14),

                                      // Middle Details
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    otherPartyName,
                                                    style: const TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 15.5,
                                                      color: AppTheme.textPrimary,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                // Lost / Found Tag
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 7,
                                                    vertical: 2.5,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: tagColor.withValues(alpha: 0.12),
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: Border.all(
                                                      color: tagColor.withValues(alpha: 0.45),
                                                      width: 0.8,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        room.itemIsLost
                                                            ? Icons.search_rounded
                                                            : Icons.check_circle_outline_rounded,
                                                        size: 10,
                                                        color: tagColor,
                                                      ),
                                                      const SizedBox(width: 3),
                                                      Text(
                                                        room.itemIsLost ? 'Lost' : 'Found',
                                                        style: TextStyle(
                                                          color: tagColor,
                                                          fontSize: 9.5,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 3),

                                            // Re: Item Title
                                            Row(
                                              children: [
                                                const Icon(
                                                  Icons.bookmark_outline_rounded,
                                                  size: 12,
                                                  color: AppTheme.secondary,
                                                ),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    'Re: ${room.itemTitle}',
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      color: AppTheme.secondary,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),

                                            // Last Message Snippet
                                            Row(
                                              children: [
                                                if (isLiveSharing) ...[
                                                  const Icon(
                                                    Icons.share_location_rounded,
                                                    size: 12,
                                                    color: AppTheme.secondary,
                                                  ),
                                                  const SizedBox(width: 4),
                                                ],
                                                Expanded(
                                                  child: Text(
                                                    room.lastMessage.isNotEmpty
                                                        ? room.lastMessage
                                                        : 'Start coordinate handover...',
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 12.5,
                                                      color: isLiveSharing
                                                          ? AppTheme.secondary
                                                          : AppTheme.textSecondary,
                                                      fontWeight: isLiveSharing
                                                          ? FontWeight.w500
                                                          : FontWeight.normal,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),

                                      // Trailing Time & Indicator
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            dateStr,
                                            style: const TextStyle(
                                              fontSize: 10.5,
                                              color: AppTheme.textMuted,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          const Icon(
                                            Icons.arrow_forward_ios_rounded,
                                            size: 12,
                                            color: AppTheme.textMuted,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilterChip(String label, int count, {Color? color}) {
    final isSelected = _filter == label;
    final activeColor = color ?? AppTheme.primary;

    return InkWell(
      onTap: () => setState(() => _filter = label),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: 0.18)
              : AppTheme.cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? activeColor
                : AppTheme.border,
            width: isSelected ? 1.2 : 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? activeColor : AppTheme.textSecondary,
              ),
            ),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected
                    ? activeColor.withValues(alpha: 0.25)
                    : AppTheme.darkBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? activeColor : AppTheme.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool trulyEmpty) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primary.withValues(alpha: 0.15),
                    AppTheme.secondary.withValues(alpha: 0.08),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: AppTheme.border,
                  width: 1.5,
                ),
              ),
              child: const Icon(
                Icons.forum_outlined,
                size: 38,
                color: AppTheme.secondary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              trulyEmpty ? 'No Conversations Yet' : 'No Matches Found',
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              trulyEmpty
                  ? 'When you match with an item finder or owner, your private chat will appear here for safe handover coordination.'
                  : 'No chats match "$_searchQuery" under "$_filter" filter.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
            if (trulyEmpty) ...[
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: () => _showStartChatSheet(context, Provider.of<FirebaseService>(context, listen: false)),
                icon: const Icon(Icons.explore_rounded, size: 16),
                label: const Text('Browse Feed & Start Chat'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays == 0 && now.day == time.day) {
      return DateFormat('hh:mm a').format(time);
    } else if (difference.inDays < 7) {
      return DateFormat('EEE, hh:mm a').format(time);
    } else {
      return DateFormat('dd MMM').format(time);
    }
  }

  void _showStartChatSheet(BuildContext context, FirebaseService firebaseService) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StreamBuilder<List<ItemModel>>(
          stream: firebaseService.getItems(),
          builder: (context, snapshot) {
            final items = (snapshot.data ?? []).where((i) => i.status == 'active').toList();

            return Container(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: AppTheme.secondary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.forum_rounded, color: AppTheme.secondary, size: 20),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Start a Conversation',
                              style: TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            Text(
                              'Select an item to connect with the reporter',
                              style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted),
                        onPressed: () => Navigator.pop(sheetContext),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Center(
                        child: Text(
                          'No active items found in the community feed.',
                          style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                        ),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.5,
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: items.length,
                        separatorBuilder: (context, index) => const Divider(color: AppTheme.border, height: 1),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final isOwn = item.reporterId == firebaseService.currentUserId;
                          final tagColor = item.isLost ? AppTheme.lostColor : AppTheme.foundColor;

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                            leading: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: tagColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                item.isLost ? Icons.search_rounded : Icons.check_circle_outline_rounded,
                                color: tagColor,
                                size: 18,
                              ),
                            ),
                            title: Text(
                              item.title,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${item.isLost ? "Lost" : "Found"} by ${isOwn ? "You" : item.reporterName} • ${item.category}',
                              style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: ElevatedButton(
                              onPressed: () async {
                                Navigator.pop(sheetContext);
                                final currentUserName = isOwn ? 'Helpful Finder' : (firebaseService.currentUser?.displayName ?? 'Anonymous');
                                final otherUserId = isOwn ? 'simulated_user_${item.id.substring(0, 4)}' : item.reporterId;

                                final room = await firebaseService.getOrCreateChatRoom(
                                  itemId: item.id,
                                  itemTitle: item.title,
                                  itemIsLost: item.isLost,
                                  ownerId: item.isLost ? (isOwn ? firebaseService.currentUserId! : otherUserId) : (isOwn ? otherUserId : firebaseService.currentUserId!),
                                  ownerName: item.isLost ? (isOwn ? currentUserName : item.reporterName) : (isOwn ? item.reporterName : currentUserName),
                                  finderId: item.isLost ? (isOwn ? otherUserId : firebaseService.currentUserId!) : (isOwn ? firebaseService.currentUserId! : otherUserId),
                                  finderName: item.isLost ? (isOwn ? item.reporterName : currentUserName) : (isOwn ? currentUserName : item.reporterName),
                                );

                                if (context.mounted) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ChatPage(chatRoom: room),
                                    ),
                                  );
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primary,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text('Chat', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

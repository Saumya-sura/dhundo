import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/chat_model.dart';
import '../services/firebase_service.dart';
import '../theme/app_theme.dart';

class ChatPage extends StatefulWidget {
  final ChatRoomModel chatRoom;

  const ChatPage({super.key, required this.chatRoom});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
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
        content: const Text('Confirming that the item has been returned? This will archive the map pin.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
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
            child: const Text('Confirm', style: TextStyle(color: AppTheme.foundColor)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final firebaseService = Provider.of<FirebaseService>(context);
    final String currentUserId = firebaseService.currentUserId ?? '';
    final isOwner = widget.chatRoom.ownerId == currentUserId;
    final otherPartyName = isOwner ? widget.chatRoom.finderName : widget.chatRoom.ownerName;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              otherPartyName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              'Re: ${widget.chatRoom.itemTitle}',
              style: const TextStyle(fontSize: 12, color: AppTheme.secondary),
            ),
          ],
        ),
        actions: [
          // Resolve button only if current user is owner or finder
          IconButton(
            icon: const Icon(Icons.check_circle_rounded, color: AppTheme.foundColor),
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppTheme.secondary.withOpacity(0.08),
            child: Row(
              children: const [
                Icon(Icons.shield_outlined, color: AppTheme.secondary, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Safety tip: Coordinate handovers in public, well-lit spaces.',
                    style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                  ),
                ),
              ],
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
                    final bubbleBg = isMe ? AppTheme.primary : AppTheme.cardBg;
                    final alignment = isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;
                    final timeStr = DateFormat('hh:mm a').format(msg.timestamp);

                    return Column(
                      crossAxisAlignment: alignment,
                      children: [
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75,
                          ),
                          decoration: BoxDecoration(
                            color: bubbleBg,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(16),
                              topRight: const Radius.circular(16),
                              bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
                              bottomRight: isMe ? Radius.zero : const Radius.circular(16),
                            ),
                            border: isMe 
                                ? null 
                                : Border.all(color: AppTheme.border, width: 0.8),
                          ),
                          child: Column(
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
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),

          // Message Input Box
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      fillColor: AppTheme.cardBg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: AppTheme.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: AppTheme.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: AppTheme.primary),
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
                    icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                    onPressed: () => _send(firebaseService),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

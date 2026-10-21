import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/firebase_service.dart';
import '../theme/app_theme.dart';
import 'map_view.dart';
import 'feed_view.dart';
import 'report_page.dart';
import 'chats_list_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final firebaseService = Provider.of<FirebaseService>(context);
    final String userName = firebaseService.currentUser?.displayName ?? 'User';

    final List<Widget> pages = [
      const MapView(),
      const FeedView(),
      ReportPage(isActive: _currentIndex == 2),
      const ChatsListPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.radar_rounded, color: AppTheme.secondary),
            const SizedBox(width: 8),
            Text(
              'DHUNDO',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 22,
                letterSpacing: 1.2,
                foreground: Paint()
                  ..shader = AppTheme.primaryGradient.createShader(
                    const Rect.fromLTWH(0.0, 0.0, 200.0, 70.0),
                  ),
              ),
            ),
          ],
        ),
        actions: [
          Row(
            children: [
              Text(
                'Hi, $userName',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.logout_rounded, color: AppTheme.lostColor, size: 20),
                tooltip: 'Sign Out',
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: AppTheme.cardBg,
                      title: const Text('Sign Out'),
                      content: const Text('Are you sure you want to sign out from Dhundo?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            firebaseService.signOut();
                          },
                          child: const Text('Sign Out', style: TextStyle(color: AppTheme.lostColor)),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: AppTheme.border.withValues(alpha: 0.4), width: 1),
          ),
        ),
        child: StreamBuilder<int>(
          stream: firebaseService.getTotalUnreadMessagesCount(),
          builder: (context, snapshot) {
            final unreadCount = snapshot.data ?? 0;

            return BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              type: BottomNavigationBarType.fixed,
              backgroundColor: AppTheme.cardBg,
              selectedItemColor: AppTheme.primaryAccent,
              unselectedItemColor: AppTheme.textMuted,
              selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              unselectedLabelStyle: const TextStyle(fontSize: 12),
              items: [
                const BottomNavigationBarItem(
                  icon: Icon(Icons.map_outlined),
                  activeIcon: Icon(Icons.map, color: AppTheme.secondary),
                  label: 'Map',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.feed_outlined),
                  activeIcon: Icon(Icons.feed, color: AppTheme.primary),
                  label: 'Feed',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.add_circle_outline_rounded),
                  activeIcon: Icon(Icons.add_circle_rounded, color: AppTheme.secondary),
                  label: 'Report',
                ),
                BottomNavigationBarItem(
                  icon: Badge(
                    isLabelVisible: unreadCount > 0,
                    label: Text(
                      unreadCount > 99 ? '99+' : '$unreadCount',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    backgroundColor: AppTheme.lostColor,
                    child: const Icon(Icons.chat_bubble_outline_rounded),
                  ),
                  activeIcon: Badge(
                    isLabelVisible: unreadCount > 0,
                    label: Text(
                      unreadCount > 99 ? '99+' : '$unreadCount',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    backgroundColor: AppTheme.lostColor,
                    child: const Icon(Icons.chat_bubble_rounded, color: AppTheme.primary),
                  ),
                  label: 'Chats',
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/item_model.dart';
import '../services/firebase_service.dart';
import '../services/google_maps_service.dart';
import '../widgets/street_view_dialog.dart';
import '../theme/app_theme.dart';
import 'chat_page.dart';

class MatchEvaluation {
  final ItemModel item;
  final int matchScore; // 0 to 100%
  final double distanceKm;
  final List<String> matchReasons;
  final String confidenceLevel; // 'High Match', 'Strong Match', 'Moderate Match'
  final Color confidenceColor;

  MatchEvaluation({
    required this.item,
    required this.matchScore,
    required this.distanceKm,
    required this.matchReasons,
    required this.confidenceLevel,
    required this.confidenceColor,
  });

  static MatchEvaluation evaluate(ItemModel target, ItemModel candidate) {
    int score = 0;
    final List<String> reasons = [];

    // 1. Category Matching (up to 30 pts)
    if (target.category.toLowerCase().trim() == candidate.category.toLowerCase().trim()) {
      score += 30;
      reasons.add('🏷️ Category: ${candidate.category}');
    }

    // 2. Distance & Spatial Proximity (up to 35 pts)
    final distanceMeters = GoogleMapsService.calculateDistanceMeters(
      target.latitude,
      target.longitude,
      candidate.latitude,
      candidate.longitude,
    );
    final distanceKm = distanceMeters / 1000.0;

    if (distanceMeters <= 300) {
      score += 35;
      reasons.add('📍 Very close (~${distanceMeters.round()}m away)');
    } else if (distanceMeters <= 1000) {
      score += 30;
      reasons.add('📍 Within 1 km (~${(distanceMeters / 100).round() * 100}m away)');
    } else if (distanceKm <= 3.0) {
      score += 22;
      reasons.add('📍 Same area (~${distanceKm.toStringAsFixed(1)} km)');
    } else if (distanceKm <= 7.0) {
      score += 15;
      reasons.add('📍 Same district (~${distanceKm.toStringAsFixed(1)} km)');
    } else {
      score += 8;
      reasons.add('📍 Within 10 km');
    }

    // 3. Temporal Proximity (up to 20 pts)
    final timeDiff = target.dateTime.difference(candidate.dateTime).abs();
    if (timeDiff.inHours <= 6) {
      score += 20;
      reasons.add('⏱️ Reported within 6 hrs');
    } else if (timeDiff.inHours <= 24) {
      score += 15;
      reasons.add('⏱️ Reported within 24 hrs');
    } else if (timeDiff.inDays <= 3) {
      score += 10;
      reasons.add('⏱️ Reported within 3 days');
    } else if (timeDiff.inDays <= 7) {
      score += 5;
      reasons.add('⏱️ Reported this week');
    }

    // 4. Keyword & Description Overlap (up to 15 pts)
    const stopWords = {
      'the', 'a', 'an', 'my', 'in', 'on', 'at', 'is', 'it', 'and', 'or', 'of',
      'to', 'with', 'for', 'lost', 'found', 'item', 'please', 'help', 'near',
      'around', 'this', 'that', 'from', 'by', 'was', 'have', 'has', 'there',
      'some', 'very', 'were', 'had', 'been', 'about'
    };

    final targetTokens = _extractTokens('${target.title} ${target.description}', stopWords);
    final candidateTokens = _extractTokens('${candidate.title} ${candidate.description}', stopWords);
    final commonTokens = targetTokens.intersection(candidateTokens).toList();

    if (commonTokens.length >= 3) {
      score += 15;
      reasons.add('🔍 Keywords: ${commonTokens.take(3).join(', ')}');
    } else if (commonTokens.length == 2) {
      score += 12;
      reasons.add('🔍 Keywords: ${commonTokens.join(', ')}');
    } else if (commonTokens.length == 1) {
      score += 8;
      reasons.add('🔍 Keyword: ${commonTokens.first}');
    }

    // Clamp score between 30% and 98%
    final finalScore = score.clamp(30, 98);

    String confidence;
    Color color;
    if (finalScore >= 80) {
      confidence = 'High Match';
      color = AppTheme.foundColor;
    } else if (finalScore >= 60) {
      confidence = 'Strong Match';
      color = AppTheme.secondary;
    } else {
      confidence = 'Moderate Match';
      color = const Color(0xFFF59E0B);
    }

    return MatchEvaluation(
      item: candidate,
      matchScore: finalScore,
      distanceKm: distanceKm,
      matchReasons: reasons,
      confidenceLevel: confidence,
      confidenceColor: color,
    );
  }

  static Set<String> _extractTokens(String text, Set<String> stopWords) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2 && !stopWords.contains(w))
        .toSet();
  }
}

class PotentialMatchesPage extends StatefulWidget {
  final ItemModel reportedItem;
  final List<ItemModel> potentialMatches;

  const PotentialMatchesPage({
    super.key,
    required this.reportedItem,
    required this.potentialMatches,
  });

  @override
  State<PotentialMatchesPage> createState() => _PotentialMatchesPageState();
}

class _PotentialMatchesPageState extends State<PotentialMatchesPage> {
  bool _submitting = false;
  late List<MatchEvaluation> _evaluations;

  @override
  void initState() {
    super.initState();
    _evaluations = widget.potentialMatches
        .map((item) => MatchEvaluation.evaluate(widget.reportedItem, item))
        .toList()
      ..sort((a, b) => b.matchScore.compareTo(a.matchScore));
  }

  void _submitReportAnyway(FirebaseService firebaseService) async {
    setState(() {
      _submitting = true;
    });

    try {
      await firebaseService.reportItem(widget.reportedItem);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.reportedItem.isLost ? "Lost" : "Found"} report posted successfully!'),
            backgroundColor: AppTheme.foundColor,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to post report: $e'),
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

  void _navigateToChat(ItemModel matchItem, FirebaseService firebaseService) async {
    try {
      final currentUserName = firebaseService.currentUser?.displayName ?? 'Anonymous';
      final chatRoom = await firebaseService.getOrCreateChatRoom(
        itemId: matchItem.id,
        itemTitle: matchItem.title,
        itemIsLost: matchItem.isLost,
        ownerId: matchItem.isLost ? matchItem.reporterId : firebaseService.currentUserId!,
        ownerName: matchItem.isLost ? matchItem.reporterName : currentUserName,
        finderId: matchItem.isLost ? firebaseService.currentUserId! : matchItem.reporterId,
        finderName: matchItem.isLost ? currentUserName : matchItem.reporterName,
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
      appBar: AppBar(
        title: const Text('Smart AI Match Engine'),
      ),
      body: Column(
        children: [
          // Informational Warning Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: AppTheme.secondary.withValues(alpha: 0.08),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.secondary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.auto_awesome, color: AppTheme.secondary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Found ${_evaluations.length} Potential Match${_evaluations.length > 1 ? "es" : ""}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Ranked by AI similarity, proximity & incident timeframe.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Matches scroll list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _evaluations.length,
              itemBuilder: (context, index) {
                final eval = _evaluations[index];
                final match = eval.item;
                final dateStr = DateFormat('MMM dd, yyyy • h:mm a').format(match.dateTime);
                final color = match.isLost ? AppTheme.lostColor : AppTheme.foundColor;

                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(
                      color: eval.matchScore >= 80
                          ? eval.confidenceColor.withValues(alpha: 0.5)
                          : AppTheme.border,
                      width: eval.matchScore >= 80 ? 1.4 : 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Match Score Header Banner
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(
                          color: eval.confidenceColor.withValues(alpha: 0.12),
                          border: Border(
                            bottom: BorderSide(
                              color: eval.confidenceColor.withValues(alpha: 0.25),
                              width: 1,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: eval.confidenceColor,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.bolt_rounded, size: 13, color: Colors.white),
                                  const SizedBox(width: 3),
                                  Text(
                                    '${eval.matchScore}% MATCH',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 11,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              eval.confidenceLevel,
                              style: TextStyle(
                                color: eval.confidenceColor,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: color, width: 0.8),
                              ),
                              child: Text(
                                match.isLost ? 'LOST' : 'FOUND',
                                style: TextStyle(
                                  color: color,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      if (match.imageUrl != null)
                        Image.network(
                          match.imageUrl!,
                          height: 140,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            height: 80,
                            color: AppTheme.darkBg,
                            child: const Icon(Icons.broken_image, size: 30),
                          ),
                        ),

                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    match.title,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textPrimary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  dateStr,
                                  style: const TextStyle(
                                    color: AppTheme.textMuted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              match.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 10),

                            // Smart Match Reasons Chips
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: eval.matchReasons.map((reason) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                                  decoration: BoxDecoration(
                                    color: AppTheme.darkBg,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: AppTheme.border.withValues(alpha: 0.8),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Text(
                                    reason,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),

                            const SizedBox(height: 10),
                            Row(
                              children: [
                                const Icon(Icons.location_on_rounded, size: 14, color: AppTheme.secondary),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    '${match.locationDescription} • ${(eval.distanceKm < 1.0) ? "${(eval.distanceKm * 1000).round()}m away" : "${eval.distanceKm.toStringAsFixed(1)} km away"}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textMuted,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),

                            const Divider(color: AppTheme.border, height: 20),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () {
                                    StreetViewDialog.show(
                                      context,
                                      latitude: match.latitude,
                                      longitude: match.longitude,
                                      locationTitle: match.locationDescription,
                                    );
                                  },
                                  icon: const Icon(Icons.streetview_rounded, size: 14, color: AppTheme.secondary),
                                  label: const Text(
                                    '360° Street View',
                                    style: TextStyle(fontSize: 11, color: AppTheme.secondary),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: AppTheme.secondary.withValues(alpha: 0.4)),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                                ElevatedButton.icon(
                                  onPressed: () => _navigateToChat(match, firebaseService),
                                  icon: const Icon(Icons.chat_bubble_rounded, size: 14),
                                  label: Text(
                                    match.isLost ? 'Contact Owner' : 'Contact Finder',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.secondary,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
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

          // Action bottom panel: Submit anyway option
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElevatedButton(
                  onPressed: _submitting ? null : () => _submitReportAnyway(firebaseService),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                        )
                      : const Text('None of these match, submit my report'),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

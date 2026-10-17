import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/firebase_service.dart';
import '../theme/app_theme.dart';

class CallOverlayPage extends StatefulWidget {
  final String chatRoomId;
  final String otherPartyName;
  final bool isCaller;

  const CallOverlayPage({
    super.key,
    required this.chatRoomId,
    required this.otherPartyName,
    required this.isCaller,
  });

  @override
  State<CallOverlayPage> createState() => _CallOverlayPageState();
}

class _CallOverlayPageState extends State<CallOverlayPage> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _waveformController;
  
  Timer? _callTimer;
  Timer? _simulatedPickupTimer;
  int _secondsElapsed = 0;
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _callInitiated = false;
  StreamSubscription? _chatSubscription;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    _waveformController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat();

    final firebaseService = Provider.of<FirebaseService>(context, listen: false);

    if (widget.isCaller) {
      _callInitiated = true;
      // Initiate call in DB
      firebaseService.initiateCall(
        widget.chatRoomId,
        firebaseService.currentUser?.displayName ?? 'Anonymous',
      );

      // Simulated pickup after 3.5 seconds for showcase / single-user testing
      _simulatedPickupTimer = Timer(const Duration(milliseconds: 3500), () async {
        if (mounted && _callTimer == null) {
          await firebaseService.acceptCall(widget.chatRoomId);
          _startCallTimer();
        }
      });
    }

    // Listen to calling updates in Firestore without prematurely closing
    _chatSubscription = firebaseService.getUserChatRooms().listen((rooms) {
      final currentRoom = rooms.where((r) => r.id == widget.chatRoomId).firstOrNull;
      
      if (currentRoom != null) {
        final status = currentRoom.callStatus;
        if (status == 'ended' && _callInitiated) {
          _endCallLocal(shouldUpdateDb: false);
        } else if (status == 'connected' && _callTimer == null) {
          _simulatedPickupTimer?.cancel();
          _startCallTimer();
        }
      }
    });
  }

  void _startCallTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _secondsElapsed++;
        });
      }
    });
    if (mounted) {
      setState(() {});
    }
  }

  void _acceptCall() async {
    _simulatedPickupTimer?.cancel();
    final firebaseService = Provider.of<FirebaseService>(context, listen: false);
    await firebaseService.acceptCall(widget.chatRoomId);
    _startCallTimer();
  }

  void _declineOrEndCall() async {
    _simulatedPickupTimer?.cancel();
    final firebaseService = Provider.of<FirebaseService>(context, listen: false);
    await firebaseService.endCall(widget.chatRoomId);
    _endCallLocal(shouldUpdateDb: true);
  }

  void _endCallLocal({required bool shouldUpdateDb}) async {
    _simulatedPickupTimer?.cancel();
    _callTimer?.cancel();
    _chatSubscription?.cancel();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Call Ended'),
          duration: Duration(seconds: 2),
        ),
      );
      Navigator.pop(context);
    }

    if (shouldUpdateDb) {
      final firebaseService = Provider.of<FirebaseService>(context, listen: false);
      // Wait a brief moment then clear signaling fields
      Future.delayed(const Duration(seconds: 2), () {
        firebaseService.resetCallStatus(widget.chatRoomId);
      });
    }
  }

  String _formatDuration(int seconds) {
    final mins = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  void dispose() {
    _simulatedPickupTimer?.cancel();
    _pulseController.dispose();
    _waveformController.dispose();
    _callTimer?.cancel();
    _chatSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final firebaseService = Provider.of<FirebaseService>(context);
    
    return StreamBuilder<List<dynamic>>(
      stream: firebaseService.getUserChatRooms(),
      builder: (context, snapshot) {
        final rooms = snapshot.data;
        final room = rooms?.where((r) => r.id == widget.chatRoomId).firstOrNull;
        final status = room?.callStatus ?? (widget.isCaller ? 'ringing' : 'incoming');

        final showIncomingView = !widget.isCaller && status == 'ringing';
        final showConnectedView = status == 'connected';
        final showOutgoingView = widget.isCaller && status == 'ringing';

        return Scaffold(
          backgroundColor: AppTheme.darkBg,
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.darkBg,
                  showConnectedView
                      ? AppTheme.primary.withValues(alpha: 0.12)
                      : AppTheme.secondary.withValues(alpha: 0.08),
                  AppTheme.darkBg
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 36.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Top Section - Caller Metadata
                    Column(
                      children: [
                        const SizedBox(height: 40),
                        ScaleTransition(
                          scale: Tween<double>(begin: 0.95, end: 1.05).animate(
                            CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
                          ),
                          child: Container(
                            width: 110,
                            height: 110,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: AppTheme.primaryGradient,
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primary.withValues(alpha: 0.4),
                                  blurRadius: 20,
                                  spreadRadius: 4,
                                )
                              ],
                            ),
                            child: Center(
                              child: Text(
                                widget.otherPartyName.isNotEmpty ? widget.otherPartyName[0].toUpperCase() : 'U',
                                style: const TextStyle(fontSize: 44, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          widget.otherPartyName,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          showIncomingView
                              ? 'Incoming Call...'
                              : showOutgoingView
                                  ? 'Calling...'
                                  : 'Call Connected',
                          style: TextStyle(
                            fontSize: 14,
                            color: showConnectedView ? AppTheme.secondary : AppTheme.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (showConnectedView) ...[
                          const SizedBox(height: 12),
                          Text(
                            _formatDuration(_secondsElapsed),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ],
                      ],
                    ),

                    // Middle Section - Simulated Audio Waves (Only when connected)
                    if (showConnectedView)
                      Container(
                        height: 60,
                        alignment: Alignment.center,
                        child: AnimatedBuilder(
                          animation: _waveformController,
                          builder: (context, child) {
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(8, (index) {
                                // Generate heights based on waves
                                final double height = 15.0 + 35.0 * (0.3 + 0.7 * (1.0 - (index - 3.5).abs() / 4.0)) * 
                                    (0.5 + 0.5 * (index % 2 == 0 ? _waveformController.value : 1.0 - _waveformController.value));
                                return Container(
                                  width: 4,
                                  height: height,
                                  margin: const EdgeInsets.symmetric(horizontal: 3),
                                  decoration: BoxDecoration(
                                    gradient: AppTheme.primaryGradient,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                );
                              }),
                            );
                          },
                        ),
                      )
                    else
                      const SizedBox(height: 60),

                    // Bottom Section - Controls
                    Column(
                      children: [
                        if (showConnectedView) ...[
                          // Audio Control buttons
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              IconButton(
                                icon: Icon(
                                  _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                                  color: _isMuted ? AppTheme.lostColor : AppTheme.textPrimary,
                                  size: 28,
                                ),
                                style: IconButton.styleFrom(
                                  backgroundColor: AppTheme.cardBg,
                                  padding: const EdgeInsets.all(16),
                                ),
                                onPressed: () {
                                  setState(() {
                                    _isMuted = !_isMuted;
                                  });
                                },
                              ),
                              IconButton(
                                icon: Icon(
                                  _isSpeakerOn ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                                  color: _isSpeakerOn ? AppTheme.secondary : AppTheme.textPrimary,
                                  size: 28,
                                ),
                                style: IconButton.styleFrom(
                                  backgroundColor: AppTheme.cardBg,
                                  padding: const EdgeInsets.all(16),
                                ),
                                onPressed: () {
                                  setState(() {
                                    _isSpeakerOn = !_isSpeakerOn;
                                  });
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 40),
                        ],

                        // Answer/Reject buttons
                        if (showIncomingView)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              // Decline Button
                              FloatingActionButton(
                                heroTag: 'declineCallBtn',
                                backgroundColor: AppTheme.lostColor,
                                onPressed: _declineOrEndCall,
                                child: const Icon(Icons.call_end_rounded, color: Colors.white),
                              ),
                              // Accept Button
                              FloatingActionButton(
                                heroTag: 'acceptCallBtn',
                                backgroundColor: AppTheme.foundColor,
                                onPressed: _acceptCall,
                                child: const Icon(Icons.call_rounded, color: Colors.white),
                              ),
                            ],
                          )
                        else
                          // Ringing or Connected - Single Decline button
                          FloatingActionButton(
                            heroTag: 'endCallBtn',
                            backgroundColor: AppTheme.lostColor,
                            onPressed: _declineOrEndCall,
                            child: const Icon(Icons.call_end_rounded, color: Colors.white),
                          ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

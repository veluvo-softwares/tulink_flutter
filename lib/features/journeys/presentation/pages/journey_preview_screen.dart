import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../core/services/location_permission_service.dart';
import '../../../../core/theme/tulink_colors.dart';
import '../../domain/entities/journey.dart';
import '../providers/journey_provider.dart';
import '../widgets/journey_preview_map.dart';
import '../../../convoy/presentation/providers/convoy_provider.dart';
import 'invite_participants_screen.dart';

class JourneyPreviewScreen extends StatefulWidget {
  final String journeyId;
  
  const JourneyPreviewScreen({
    super.key,
    required this.journeyId,
  });

  static const String routeName = '/journey-preview';

  @override
  State<JourneyPreviewScreen> createState() => _JourneyPreviewScreenState();
}

class _JourneyPreviewScreenState extends State<JourneyPreviewScreen> 
    with TickerProviderStateMixin {
  bool _showCountdown = false;
  bool _isStartingJourney = false;
  int _countdownValue = 5;
  Timer? _countdownTimer;
  late AnimationController _countdownAnimationController;
  late Animation<double> _countdownScale;
  bool _showGoMessage = false;

  @override
  void initState() {
    super.initState();
    
    // Initialize animation controller
    _countdownAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _countdownScale = Tween<double>(
      begin: 0.5,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _countdownAnimationController,
      curve: Curves.elasticOut,
    ));
    
    // Load journey details and initialize invitation provider when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<JourneyProvider>().fetchJourneyById(widget.journeyId);
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _countdownAnimationController.dispose();
    super.dispose();
  }


  Future<void> _startJourneyCountdown() async {
    // Ensure location permission is granted BEFORE the countdown begins —
    // the convoy goes ACTIVE on the backend once the countdown completes.
    final hasPermission =
        await LocationPermissionService.hasLocationPermission();

    if (!hasPermission) {
      final result =
          await LocationPermissionService.requestLocationPermission();

      if (!result.granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result.failure?.message ??
                    'Location access is required to start a convoy.',
              ),
              backgroundColor: Colors.red,
              action: SnackBarAction(
                label: 'Settings',
                textColor: Colors.white,
                onPressed: LocationPermissionService.openAppSettings,
              ),
            ),
          );
        }
        return; // Do not start countdown
      }
    }

    if (!mounted) return;

    // Permission confirmed — start the animated countdown
    setState(() {
      _showCountdown = true;
      _countdownValue = 5;
      _showGoMessage = false;
    });

    _startCountdownTimer();
  }

  Future<void> _onCountdownComplete() async {
    if (!mounted) return;
    
    setState(() {
      _isStartingJourney = true;
    });

    try {
      // Start the journey via backend API
      final success = await context.read<JourneyProvider>().startJourney(widget.journeyId);
      
      if (success && mounted) {
        // Start convoy coordination in the background
        final convoyProvider = context.read<ConvoyProvider>();
        
        // Initialize convoy coordination for real-time tracking
        print('🚀 Starting convoy coordination for journey: ${widget.journeyId}');
        convoyProvider.startCoordination(widget.journeyId);
        
        // Small delay to ensure convoy starts properly
        await Future.delayed(const Duration(milliseconds: 500));
        
        if (mounted) {
          // Navigate to convoy map screen (main map with convoy UI)
          Navigator.of(context).pushReplacementNamed(
            '/mapview', // Use main map screen which shows convoy UI when journey is active
            arguments: widget.journeyId,
          );
        }
      } else {
        // Handle start journey failure
        _handleJourneyStartFailure('Failed to start journey. Please try again.');
      }
    } catch (e) {
      print('❌ Error starting journey: $e');
      _handleJourneyStartFailure('Error starting journey: ${e.toString()}');
    }
  }

  void _handleJourneyStartFailure(String message) {
    if (!mounted) return;
    
    setState(() {
      _isStartingJourney = false;
      _showCountdown = false;
      _showGoMessage = false;
      _countdownValue = 5;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _startCountdownTimer() {
    _countdownAnimationController.forward();
    
    // Haptic feedback for countdown start
    HapticFeedback.mediumImpact();
    
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdownValue > 1) {
        setState(() {
          _countdownValue--;
        });
        
        // Different haptic feedback for each countdown number
        if (_countdownValue == 1) {
          HapticFeedback.heavyImpact(); // Strong vibration for final number
        } else {
          HapticFeedback.lightImpact(); // Light vibration for other numbers
        }
        
        // Reset and restart animation for each number
        _countdownAnimationController.reset();
        _countdownAnimationController.forward();
      } else {
        // Show GO! message
        timer.cancel();
        setState(() {
          _showGoMessage = true;
        });
        
        // Double haptic feedback for GO!
        HapticFeedback.heavyImpact();
        Future.delayed(const Duration(milliseconds: 100), () {
          HapticFeedback.heavyImpact();
        });
        
        // Animate GO! message
        _countdownAnimationController.reset();
        _countdownAnimationController.forward();
        
        // Start journey after showing GO! for 1 second
        Future.delayed(const Duration(seconds: 1), () {
          _onCountdownComplete();
        });
      }
    });
  }

  void _onCancelCountdown() {
    _countdownTimer?.cancel();
    _countdownAnimationController.stop();
    setState(() {
      _showCountdown = false;
      _showGoMessage = false;
      _countdownValue = 5;
    });
  }

  void _navigateToEditJourney(Journey journey) {
    Navigator.of(context).pushNamed(
      '/edit-journey',
      arguments: journey,
    );
  }

  bool _canStartJourney(Journey? journey) {
    if (journey == null) return false;
    if (journey.status != JourneyStatus.PENDING) return false;
    
    // Journey can start if it's in pending status
    return true;
  }

  Color _getStatusColor(JourneyStatus status, TulinkColors colors) {
    switch (status) {
      case JourneyStatus.PENDING:
        return Colors.orange;
      case JourneyStatus.ACTIVE:
        return colors.tulinkBlue;
      case JourneyStatus.COMPLETED:
        return colors.tulinkBlue;
      case JourneyStatus.CANCELLED:
        return colors.electricRed;
      case JourneyStatus.PAUSED:
        return colors.silver;
    }
  }

  String _getStatusText(JourneyStatus status) {
    switch (status) {
      case JourneyStatus.PENDING:
        return 'PENDING';
      case JourneyStatus.ACTIVE:
        return 'ACTIVE';
      case JourneyStatus.COMPLETED:
        return 'COMPLETED';
      case JourneyStatus.CANCELLED:
        return 'CANCELLED';
      case JourneyStatus.PAUSED:
        return 'PAUSED';
    }
  }

  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'JUST NOW';
    }
  }

  Widget _buildParticipantsSection(Journey journey, TulinkColors colors) {
    final participants = journey.participants ?? [];
    final isPending = journey.status == JourneyStatus.PENDING;
    final isLeader = true; // The preview screen is always shown to the journey leader

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.brushedSteel.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'CONVOY PARTICIPANTS',
                style: TextStyle(
                  color: colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (isPending && isLeader)
                GestureDetector(
                  onTap: () => Navigator.of(context).pushNamed(
                    InviteParticipantsScreen.routeName,
                    arguments: journey.id,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: colors.electricRed,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.person_add, color: colors.white, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          'Invite',
                          style: TextStyle(
                            color: colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (participants.isEmpty)
            Text(
              'No participants yet',
              style: TextStyle(
                color: colors.silver,
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
            )
          else
            ...participants.map((p) => _buildParticipantRow(p, colors)),
        ],
      ),
    );
  }

  Widget _buildParticipantRow(Participant p, TulinkColors colors) {
    final isLeader = p.role.toUpperCase() == 'LEADER';
    final displayName = p.displayName ?? p.userId;

    Color statusColor;
    switch (p.status.toUpperCase()) {
      case 'ACTIVE':
        statusColor = Colors.green;
        break;
      case 'ACCEPTED':
        statusColor = colors.tulinkBlue;
        break;
      case 'INVITED':
        statusColor = Colors.orange;
        break;
      default:
        statusColor = colors.silver;
    }

    String initials;
    final parts = displayName.trim().split(' ');
    if (parts.length >= 2) {
      initials = '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (displayName.isNotEmpty) {
      initials = displayName[0].toUpperCase();
    } else {
      initials = '?';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isLeader
                  ? colors.electricRed.withOpacity(0.15)
                  : colors.brushedSteel,
              shape: BoxShape.circle,
              border: Border.all(
                color: isLeader
                    ? colors.electricRed.withOpacity(0.4)
                    : colors.silver.withOpacity(0.2),
              ),
            ),
            child: Center(
              child: Text(
                initials,
                style: TextStyle(
                  color: isLeader ? colors.electricRed : colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: TextStyle(
                    color: colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  p.role.toUpperCase(),
                  style: TextStyle(
                    color: isLeader ? colors.electricRed : colors.silver,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: statusColor.withOpacity(0.4)),
            ),
            child: Text(
              p.status.toUpperCase(),
              style: TextStyle(
                color: statusColor,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(TulinkColors colors, String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.cardDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.brushedSteel.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: colors.electricRed, size: 20),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              color: colors.silver,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;
    return Scaffold(
      backgroundColor: colors.carbonBlack,
      body: Consumer<JourneyProvider>(
        builder: (context, journeyProvider, child) {
          final journey = journeyProvider.currentJourney;
          
          if (journeyProvider.isLoading && journey == null) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (journey == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: colors.silver,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Journey not found',
                    style: TextStyle(
                      color: colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please check your connection and try again',
                    style: TextStyle(
                      color: colors.silver,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.electricRed,
                    ),
                    child: const Text('Go Back'),
                  ),
                ],
              ),
            );
          }

          return Stack(
            children: [
              // Main content - Single scrollable column
              SingleChildScrollView(
                child: Column(
                  children: [
                  // App Bar
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
                          ),
                          const Spacer(),
                          Text(
                            'Journey Preview',
                            style: TextStyle(
                              color: colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () {
                              // Journey options menu
                            },
                            icon: const Icon(Icons.more_vert, color: Colors.white, size: 24),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Compact Map View
                  Container(
                    height: 180,
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colors.brushedSteel.withOpacity(0.3)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        children: [
                          JourneyPreviewMap(journey: journey),],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Journey Title and Status
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            journey.name,
                            style: TextStyle(
                              color: colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: _getStatusColor(journey.status, colors).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: _getStatusColor(journey.status, colors),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            _getStatusText(journey.status),
                            style: TextStyle(
                              color: _getStatusColor(journey.status, colors),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Subtitle
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Text(
                          'CONVOY • ',
                          style: TextStyle(
                            color: colors.silver,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          journey.createdAt != null 
                              ? 'CREATED ${_getTimeAgo(journey.createdAt!)}'
                              : 'CREATED RECENTLY',
                          style: TextStyle(
                            color: colors.silver,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Destination Card
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colors.cardDark,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colors.brushedSteel.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.location_on,
                          color: colors.electricRed,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'DESTINATION',
                                style: TextStyle(
                                  color: colors.silver,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                journey.destinationAddress,
                                style: TextStyle(
                                  color: colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => _navigateToEditJourney(journey),
                          icon: Icon(
                            Icons.edit,
                            color: colors.silver,
                            size: 20,
                          ),
                          tooltip: 'Edit journey',
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Journey Info Cards Row
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildInfoCard(
                            colors,
                            'TYPE',
                            'Convoy',
                            Icons.route,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildInfoCard(
                            colors,
                            'LAG LIMIT',
                            '${journey.lagThresholdMeters}m',
                            Icons.speed,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildInfoCard(
                            colors,
                            'DRIVERS',
                            '${journey.participants?.length ?? 1}',
                            Icons.group,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Participants Section
                  _buildParticipantsSection(journey, colors),

                  const SizedBox(height: 16),

                  // Start Convoy Button
                  Container(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _canStartJourney(journey) && !_showCountdown && !_isStartingJourney
                            ? _startJourneyCountdown
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.electricRed,
                          disabledBackgroundColor: colors.silver.withOpacity(0.3),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isStartingJourney
                            ? const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                   SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  ),
                                   SizedBox(width: 12),
                                   Text(
                                    'STARTING CONVOY...',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ],
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                   Icon(Icons.play_arrow, size: 24),
                                   SizedBox(width: 8),
                                   Text(
                                    'Start Convoy',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
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

              // Countdown Overlay
              if (_showCountdown)
                Container(
                  color: colors.carbonBlack.withOpacity(0.95),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Animated countdown number or GO! message
                        AnimatedBuilder(
                          animation: _countdownScale,
                          builder: (context, child) {
                            return Transform.scale(
                              scale: _countdownScale.value,
                              child: Container(
                                width: 200,
                                height: 200,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: colors.electricRed,
                                    width: 4,
                                  ),
                                  color: colors.electricRed.withOpacity(0.1),
                                ),
                                child: Center(
                                  child: _showGoMessage
                                      ? Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              'GO!',
                                              style: TextStyle(
                                                color: colors.electricRed,
                                                fontSize: 48,
                                                fontWeight: FontWeight.w900,
                                                letterSpacing: 2.0,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Icon(
                                              Icons.rocket_launch,
                                              color: colors.electricRed,
                                              size: 32,
                                            ),
                                          ],
                                        )
                                      : Text(
                                          '$_countdownValue',
                                          style: TextStyle(
                                            color: colors.electricRed,
                                            fontSize: 72,
                                            fontWeight: FontWeight.w900,
                                            fontFamily: 'Rajdhani',
                                          ),
                                        ),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 40),
                        if (!_showGoMessage) ...[
                          Text(
                            'CONVOY STARTING IN',
                            style: TextStyle(
                              color: colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 2.0,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Get ready for real-time coordination',
                            style: TextStyle(
                              color: colors.silver,
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          const SizedBox(height: 48),
                          ElevatedButton(
                            onPressed: _onCancelCountdown,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colors.silver.withOpacity(0.8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 32,
                                vertical: 12,
                              ),
                            ),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ] else ...[
                          Text(
                            'CONVOY ACTIVATED',
                            style: TextStyle(
                              color: colors.electricRed,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2.0,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(colors.electricRed),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Text(
                                'Initializing real-time tracking...',
                                style: TextStyle(
                                  color: colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

              // Error display
              if (journeyProvider.error != null)
                Positioned(
                  top: 100,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colors.electricRed.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error, color: Colors.white),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            journeyProvider.error!,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            // Clear error - would need method in provider
                          },
                          icon: const Icon(Icons.close, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
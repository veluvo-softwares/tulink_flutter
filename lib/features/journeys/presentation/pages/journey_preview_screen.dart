import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/tulink_colors.dart';
import '../../domain/entities/journey.dart';
import '../providers/journey_provider.dart';
import '../providers/invitation_provider.dart';
import '../widgets/journey_preview_map.dart';
import '../widgets/participant_list_widget.dart';
import '../widgets/convoy_countdown_widget.dart';
import '../widgets/journey_info_card.dart';

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

class _JourneyPreviewScreenState extends State<JourneyPreviewScreen> {
  bool _showCountdown = false;
  bool _isStartingJourney = false;

  @override
  void initState() {
    super.initState();
    // Load journey details and initialize invitation provider when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<JourneyProvider>().fetchJourneyById(widget.journeyId);
      context.read<InvitationProvider>().initializeForJourney(widget.journeyId);
    });
  }

  Future<void> _startJourneyCountdown() async {
    setState(() {
      _showCountdown = true;
    });
  }

  Future<void> _onCountdownComplete() async {
    setState(() {
      _isStartingJourney = true;
    });

    try {
      // Start the journey via backend API
      final success = await context.read<JourneyProvider>().startJourney(widget.journeyId);
      
      if (success && mounted) {
        // Navigate to convoy map screen
        Navigator.of(context).pushReplacementNamed(
          '/convoy-map',
          arguments: widget.journeyId,
        );
      } else {
        // Handle start journey failure
        setState(() {
          _isStartingJourney = false;
          _showCountdown = false;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to start journey. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isStartingJourney = false;
        _showCountdown = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error starting journey: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _onCancelCountdown() {
    setState(() {
      _showCountdown = false;
    });
  }

  bool _canStartJourney(Journey? journey, InvitationProvider invitationProvider) {
    if (journey == null) return false;
    if (journey.status != JourneyStatus.PENDING) return false;
    
    // Journey can start if there's at least one participant (the leader)
    // and no pending invitations for smoother start process
    return invitationProvider.canStartJourney;
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


  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;
    
    return Scaffold(
      backgroundColor: colors.carbonBlack,
      body: Consumer2<JourneyProvider, InvitationProvider>(
        builder: (context, journeyProvider, invitationProvider, child) {
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
                          JourneyPreviewMap(journey: journey),
                          // Live tracking indicator
                          Positioned(
                            bottom: 12,
                            left: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.7),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'LIVE TRACKING',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
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
                  JourneyInfoCard(
                    child: JourneyInfoCardContent(
                      icon: Icon(
                        Icons.location_on,
                        color: colors.electricRed,
                        size: 24,
                      ),
                      title: 'DESTINATION',
                      subtitle: journey.destinationAddress,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Journey Info Cards Row
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: JourneyInfoCardGrid(
                      items: [
                        JourneyInfoCardItem(
                          title: 'TYPE',
                          value: 'Convoy',
                          icon: Icons.route,
                        ),
                        JourneyInfoCardItem(
                          title: 'LAG LIMIT',
                          value: '${journey.lagThresholdMeters}',
                          icon: Icons.speed,
                        ),
                        JourneyInfoCardItem(
                          title: 'DRIVERS',
                          value: '${invitationProvider.totalParticipantsCount}',
                          icon: Icons.group,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Participants Section
                  JourneyInfoCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Header
                        JourneyInfoCardHeader(
                          title: 'CONVOY PARTICIPANTS',
                          trailing: Text(
                            '${invitationProvider.totalParticipantsCount} ${invitationProvider.pendingInvitations.isNotEmpty ? '+ ${invitationProvider.pendingInvitations.length} pending' : ''}',
                            style: TextStyle(
                              color: colors.silver,
                              fontSize: 12,
                            ),
                          ),
                        ),

                        // Participants List (Non-scrollable)
                        Padding(
                          padding: const EdgeInsets.only(
                            left: 16,
                            right: 16,
                            bottom: 16,
                          ),
                          child: ParticipantListWidget(journeyId: widget.journeyId),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Start Convoy Button
                  Container(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _canStartJourney(journey, invitationProvider) && !_showCountdown && !_isStartingJourney
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
                            ? Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Text(
                                    'STARTING CONVOY...',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ],
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.play_arrow, size: 24),
                                  const SizedBox(width: 8),
                                  const Text(
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
                ConvoyCountdownWidget(
                  onCountdownComplete: _onCountdownComplete,
                  onCancel: _onCancelCountdown,
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
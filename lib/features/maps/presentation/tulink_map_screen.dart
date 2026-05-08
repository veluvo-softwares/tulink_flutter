import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:tulink_flutter/features/analytics/presentation/providers/analytics_provider.dart';
import '../../journeys/presentation/providers/journey_provider.dart';
import '../../journeys/domain/entities/journey.dart';
import '../../convoy/presentation/providers/convoy_provider.dart';
import '../../convoy/presentation/widgets/convoy_status_bar.dart';
import '../../convoy/presentation/widgets/convoy_bottom_sheet.dart';
import '../../convoy/presentation/widgets/convoy_metrics_bottom_sheet.dart';
import '../../convoy/presentation/widgets/driver_marker.dart';
import '../../convoy/presentation/widgets/convoy_route_line.dart';
import '../../convoy/presentation/widgets/journey_progress_screen.dart';
import '../../convoy/domain/entities/convoy_snapshot.dart';
import '../../convoy/domain/entities/member_position.dart';
import '../../auth/presentation/providers/auth_provider.dart';
import '../../analytics/presentation/screens/journey_details_screen.dart';
import 'widgets/map_journey_overlay.dart';
import 'widgets/map_header_overlay.dart';

class TulinkMapScreen extends StatefulWidget {
  const TulinkMapScreen({super.key});

  static const String routeName = '/mapview';

  @override
  State<TulinkMapScreen> createState() => _TulinkMapScreenState();
}

class _TulinkMapScreenState extends State<TulinkMapScreen> {
  MapboxMap? _mapboxMap;
  PointAnnotationManager? _pointAnnotationManager;
  String? _activeJourneyId;
  bool _isConvoyCoordinationActive = false;
  ConvoySnapshot? _lastSnapshot;
  int _lastUpdateHash = 0;

  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    _pointAnnotationManager = 
        await mapboxMap.annotations.createPointAnnotationManager();
    
    // Enable user location with defensive guards
    await _enableUserLocation(mapboxMap);

    await _updateMarkers();
    _checkAndStartConvoyCoordination();
  }

  /// Enable user location with proper permission and auth checks
  Future<void> _enableUserLocation(MapboxMap mapboxMap) async {
    try {
      // Check if user is authenticated
      final authProvider = context.read<AuthProvider>();
      final currentUser = authProvider.user;
      
      if (currentUser == null) {
        print('⚠️ User not authenticated, skipping user location');
        return;
      }
      
      // Enable user location component (blue dot)
      await mapboxMap.location.updateSettings(LocationComponentSettings(
        enabled: true,
        pulsingEnabled: true,
      ));
      
      print('✅ User location component enabled for ${currentUser.id}');
    } catch (e) {
      print('❌ Failed to enable user location: $e');
      // Continue without user location rather than crashing
    }
  }

  Future<void> _updateMarkers() async {
    if (_mapboxMap == null) return;

    // Get convoy snapshot and current user
    final convoyProvider = context.read<ConvoyProvider>();
    final authProvider = context.read<AuthProvider>();
    final currentUserId = authProvider.user?.id;
    
    // Get convoy snapshot filtered to exclude current user
    final convoySnapshot = currentUserId != null 
        ? convoyProvider.getDisplaySnapshot(currentUserId)
        : convoyProvider.snapshot;

    // Generate a hash to check if the snapshot has actually changed
    final currentHash = _generateSnapshotHash(convoySnapshot);
    
    // Only update if the snapshot has changed
    if (currentHash != _lastUpdateHash) {
      _lastUpdateHash = currentHash;
      final isFirstUpdate = _lastSnapshot == null;
      _lastSnapshot = convoySnapshot;
      
      if (convoySnapshot != null && currentUserId != null) {
        // Update convoy visualization with route line and member markers
        if (isFirstUpdate) {
          // First time: add convoy visualization
          await ConvoyRouteLine.addConvoyMarkers(_mapboxMap!, convoySnapshot, currentUserId);
          await ConvoyRouteLine.addConvoyRoute(_mapboxMap!, convoySnapshot, currentUserId);
        } else {
          // Subsequent updates: use update methods for better performance
          await ConvoyRouteLine.addConvoyMarkers(_mapboxMap!, convoySnapshot, currentUserId);
          await ConvoyRouteLine.updateConvoyRoute(_mapboxMap!, convoySnapshot, currentUserId);
        }
        
        print('✅ Updated convoy markers: ${convoySnapshot.members.length} members');
      } else {
        // Remove convoy visualization when no active convoy
        await ConvoyRouteLine.removeConvoyMarkers(_mapboxMap!);
        await ConvoyRouteLine.removeConvoyRoute(_mapboxMap!);
        print('✅ Removed convoy visualization');
        _lastSnapshot = null; // Reset for next convoy session
      }
    }
  }

  /// Generate a simple hash of the convoy snapshot for change detection
  int _generateSnapshotHash(ConvoySnapshot? snapshot) {
    if (snapshot == null) return 0;
    
    int hash = 0;
    hash ^= snapshot.members.length.hashCode;
    hash ^= snapshot.destination.latitude.hashCode;
    hash ^= snapshot.destination.longitude.hashCode;
    
    // Include member positions in hash
    for (final member in snapshot.members.values) {
      hash ^= member.latitude.hashCode;
      hash ^= member.longitude.hashCode;
      hash ^= member.timestamp.hashCode;
      hash ^= (member.isMoving ? 1 : 0).hashCode;
    }
    
    return hash;
  }


  /// Check if convoy coordination should be started
  void _checkAndStartConvoyCoordination() {
    final journeyProvider = context.read<JourneyProvider>();
    final convoyProvider = context.read<ConvoyProvider>();
    final currentJourney = journeyProvider.currentJourney;

    // Start convoy coordination if there's an active journey
    if (currentJourney != null && 
        currentJourney.status == JourneyStatus.ACTIVE &&
        !_isConvoyCoordinationActive) {
      
      _activeJourneyId = currentJourney.id;
      _isConvoyCoordinationActive = true;
      
      // Start convoy coordination
      convoyProvider.startCoordination(currentJourney.id);
    }
  }

  /// Stop convoy coordination when leaving the map
  void _stopConvoyCoordination() {
    if (_isConvoyCoordinationActive) {
      final convoyProvider = context.read<ConvoyProvider>();
      convoyProvider.stopCoordination();
      _isConvoyCoordinationActive = false;
      _activeJourneyId = null;
    }
  }

  /// Show convoy bottom sheet with member list
  void _showConvoyBottomSheet() {
    final convoyProvider = context.read<ConvoyProvider>();
    final authProvider = context.read<AuthProvider>();
    final currentUserId = authProvider.user?.id;
    
    // For bottom sheet member list, show filtered snapshot (others only)
    final snapshot = currentUserId != null 
        ? convoyProvider.getDisplaySnapshot(currentUserId)
        : convoyProvider.getFullSnapshot();

    if (snapshot != null) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => ConvoyBottomSheet(
          snapshot: snapshot,
          onMemberTap: (member) {
            // TODO: Center map on member position
            Navigator.pop(context);
          },
          onClose: () => Navigator.pop(context),
        ),
      );
    }
  }

  /// Show convoy management options
  void _showConvoyManagementOptions() {
    final convoyProvider = context.read<ConvoyProvider>();
    final journeyProvider = context.read<JourneyProvider>();
    final currentJourney = journeyProvider.currentJourney;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: Colors.grey.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.refresh, color: Colors.blue),
              title: const Text('Refresh Convoy Data', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                if (currentJourney != null) {
                  convoyProvider.refreshSnapshot(currentJourney.id);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Refreshing convoy data...')),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.wifi_off, color: Colors.orange),
              title: const Text('Reconnect to Convoy', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                if (currentJourney != null) {
                  convoyProvider.stopCoordination().then((_) {
                    convoyProvider.startCoordination(currentJourney.id);
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Reconnecting to convoy...')),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.error_outline, color: Colors.red),
              title: const Text('Clear Error', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                convoyProvider.clearError();
              },
            ),
            ListTile(
              leading: const Icon(Icons.stop, color: Colors.red),
              title: const Text('End Journey', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _showEndJourneyConfirmation();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// End the journey and stop convoy coordination
  Future<void> _endJourney() async {
    final convoyProvider = context.read<ConvoyProvider>();
    final journeyProvider = context.read<JourneyProvider>();
    
    // Stop convoy coordination
    convoyProvider.stopCoordination();
    
    // End the journey (set status to completed)
    final currentJourney = journeyProvider.currentJourney;
    if (currentJourney != null) {
      final success = await journeyProvider.endJourney(currentJourney.id);
      
      if (success && context.mounted) {
        // Get the updated journey with completed status
        final completedJourney = journeyProvider.currentJourney;
        
        if (completedJourney != null) {
          // Navigate to journey details screen with Done button
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => JourneyDetailsScreen(
                journey: completedJourney,
                showDoneButton: true,
              ),
            ),
          );
        } else {
          // Fallback: navigate to home if no journey data
          Navigator.of(context).pop();
        }
      } else {
        // Show error message
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to end journey. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  /// Show confirmation dialog for ending journey
  void _showEndJourneyConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('End Journey?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to end this convoy journey? This will stop coordination for all members.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _endJourney();
            },
            child: const Text('End Journey', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  /// Show convoy metrics bottom sheet
  void _showConvoyMetricsBottomSheet() {
    final convoyProvider = context.read<ConvoyProvider>();
    final journeyProvider = context.read<JourneyProvider>();
    final authProvider = context.read<AuthProvider>();
    final currentUserId = authProvider.user?.id;
    final currentJourney = journeyProvider.currentJourney;
    
    // For metrics, use full snapshot to include all members for distance calculations
    final snapshot = convoyProvider.getFullSnapshot();

    if (snapshot != null && currentJourney != null) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => ConvoyMetricsBottomSheet(
          snapshot: snapshot,
          journeyName: currentJourney.name,
          onEndJourney: () {
            Navigator.pop(context);
            // TODO: Implement journey end functionality
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('End journey functionality coming soon!')),
            );
          },
        ),
      );
    }
  }

  @override
  void dispose() {
    // Don't stop convoy coordination when leaving map screen
    // The journey should continue in the background
    // Only stop convoy coordination when journey is actually ended
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Listen to journey and convoy changes to update markers
    final currentJourney = context.watch<JourneyProvider>().currentJourney;
    final convoySnapshot = context.watch<ConvoyProvider>().snapshot;
    final convoyConnectionState = context.watch<ConvoyProvider>().connectionState;
    final convoyError = context.watch<ConvoyProvider>().errorMessage;
    
    // Update markers when convoy state changes
    if (_mapboxMap != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateMarkers());
    }

    // Check convoy coordination state
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAndStartConvoyCoordination());

    return Scaffold(
      body: Stack(
        children: [
          // Standard Mapbox Map
          RepaintBoundary(
            child: MapWidget(
              key: const ValueKey('mapbox_map'),
              onMapCreated: _onMapCreated,
              styleUri: MapboxStyles.DARK,
              cameraOptions: CameraOptions(
                center: Point(
                  coordinates: Position(36.8219, -1.2921), // Nairobi
                ),
                zoom: 10, // Zoom in more for convoy coordination
              ),
            ),
          ),
          
          // Convoy Status Bar - Show when active journey exists
          if (currentJourney != null && currentJourney.status == JourneyStatus.ACTIVE)
            Align(
              alignment: Alignment.topCenter,
              child: GestureDetector(
                onTap: _showConvoyBottomSheet,
                onLongPress: _showConvoyManagementOptions,
                child: ConvoyStatusBar(
                  snapshot: convoySnapshot,
                  connectionState: convoyConnectionState,
                  onTap: _showConvoyBottomSheet,
                ),
              ),
            ),
          
          // Map Header - Top Overlay (when no active journey)
          if (currentJourney == null || currentJourney.status != JourneyStatus.ACTIVE)
            const Align(
              alignment: Alignment.topCenter,
              child: MapHeaderOverlay(),
            ),

          // Back Button - Top Left
          Positioned(
            top: 50,
            left: 16,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A).withValues(alpha: 0.9),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(
                  Icons.arrow_back,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
          ),
            
          // Journey Progress Card - Bottom Overlay
          if (currentJourney != null && currentJourney.status == JourneyStatus.ACTIVE)
            Align(
              alignment: Alignment.bottomCenter,
              child: JourneyProgressCard(
                journey: currentJourney,
                convoySnapshot: convoySnapshot,
                onEndJourney: _showEndJourneyConfirmation,
              ),
            ),
            
          // Map Bottom Bar - Show when no active journey
          if (currentJourney == null || currentJourney.status != JourneyStatus.ACTIVE)
            const Align(
              alignment: Alignment.bottomCenter,
              child: MapJourneyOverlay(),
            ),

          // Error Banner - Show when convoy has errors
          if (convoyError != null && convoyError.isNotEmpty)
            Align(
              alignment: Alignment.topCenter,
              child: Container(
                margin: const EdgeInsets.only(top: 120, left: 16, right: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade700),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        convoyError,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _showConvoyManagementOptions,
                      icon: const Icon(Icons.settings, color: Colors.white, size: 20),
                      tooltip: 'Convoy Management',
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      // Convoy Metrics FAB - Show when active convoy exists
      floatingActionButton: (currentJourney != null && 
          currentJourney.status == JourneyStatus.ACTIVE && 
          convoySnapshot != null &&
          convoySnapshot.members.isNotEmpty) 
        ? FloatingActionButton(
            onPressed: _showConvoyMetricsBottomSheet,
            backgroundColor: const Color(0xFFE53E3E),
            child: const Icon(
              Icons.analytics_outlined,
              color: Colors.white,
            ),
          )
        : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tulink_flutter/core/services/car_toast_service.dart';
import 'package:tulink_flutter/features/journeys/presentation/pages/journey_preview_screen.dart';
import '../../../../core/theme/tulink_colors.dart';
import '../../../maps/presentation/providers/map_provider.dart';
import '../providers/journey_provider.dart';
import '../../domain/entities/journey.dart';

class CreateJourneyScreen extends StatefulWidget {
  final Journey? journey;
  final bool isEdit;
  
  const CreateJourneyScreen({
    super.key,
    this.journey,
    this.isEdit = false,
  });

  static const String routeName = '/create-journey';
  static const String editRouteName = '/edit-journey';

  @override
  State<CreateJourneyScreen> createState() => _CreateJourneyScreenState();
}

class _CreateJourneyScreenState extends State<CreateJourneyScreen> {
  final _nameController = TextEditingController();
  final _searchController = TextEditingController();
  final _lagController = TextEditingController(text: '500');
  
  double? _selectedLat;
  double? _selectedLng;
  String? _selectedAddress;
  bool _isSettingSelectedValue = false;

  @override
  void initState() {
    super.initState();
    if (widget.isEdit && widget.journey != null) {
      _initializeEditMode();
    }
  }

  void _initializeEditMode() {
    final journey = widget.journey!;
    _nameController.text = journey.name;
    _lagController.text = journey.lagThresholdMeters.toString();
    
    // Initialize destination from journey without triggering search
    setState(() {
      _selectedLat = journey.destination.latitude;
      _selectedLng = journey.destination.longitude;
      _selectedAddress = journey.destinationAddress;
      _isSettingSelectedValue = true;
      _searchController.text = journey.destinationAddress;
      _isSettingSelectedValue = false;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _searchController.dispose();
    _lagController.dispose();
    super.dispose();
  }

  Future<void> _onCreateJourney() async {
    if (_nameController.text.isEmpty || _selectedLat == null || _selectedLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields and select a destination')),
      );
      return;
    }

    final journeyProvider = context.read<JourneyProvider>();
    bool success;
    
    if (widget.isEdit && widget.journey != null) {
      // Update existing journey
      final updateData = {
        'name': _nameController.text,
        'destinationAddress': _selectedAddress ?? '',
        'destination': {
          'latitude': _selectedLat!,
          'longitude': _selectedLng!,
        },
        'lagThresholdMeters': int.tryParse(_lagController.text) ?? 500,
      };
      
      success = await journeyProvider.updateJourney(
        journeyId: widget.journey!.id,
        updateData: updateData,
      );
    } else {
      // Create new journey
      success = await journeyProvider.createJourney(
        name: _nameController.text,
        latitude: _selectedLat!,
        longitude: _selectedLng!,
        destinationAddress: _selectedAddress ?? '',
        lagThresholdMeters: int.tryParse(_lagController.text) ?? 500,
      );
    }

    if (!mounted) return;

    if (success) {
      if (widget.isEdit) {
        // Return to previous screen (journey preview)
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Journey updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        // Navigate to journey preview for new journey
        await Navigator.of(context).pushNamed(
          JourneyPreviewScreen.routeName,
          arguments: journeyProvider.currentJourney?.id,
        );
      }
    } else {
      final message = journeyProvider.error;
      if (message != null) {
        context.showErrorToast(message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;
    final journeyProvider = context.watch<JourneyProvider>();

    return Scaffold(
      backgroundColor: colors.carbonBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(widget.isEdit ? 'EDIT JOURNEY' : 'CREATE JOURNEY'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildLabel("JOURNEY NAME"),
            const SizedBox(height: 8),
            _buildTextField(
              controller: _nameController,
              hintText: "Enter journey name (e.g., Road Trip to NYC)",
            ),
            const SizedBox(height: 24),
            
            _buildLabel("DESTINATION SEARCH"),
            const SizedBox(height: 8),
            _buildTextField(
              controller: _searchController,
              hintText: "Search for a place...",
              onChanged: (value) {
                if (!_isSettingSelectedValue) {
                  // Clear selection when user types manually
                  if (_selectedLat != null) {
                    setState(() {
                      _selectedLat = null;
                      _selectedLng = null;
                      _selectedAddress = null;
                    });
                  }
                  context.read<MapProvider>().searchPlaces(value);
                }
              },
              suffixIcon: const Icon(Icons.search, color: Colors.white54),
            ),
            
            Consumer<MapProvider>(
              builder: (context, mapProvider, child) {
                if (mapProvider.isSearching) {
                  return Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colors.cardDark,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colors.brushedSteel),
                    ),
                    child: const Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white54,
                          ),
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Searching...',
                          style: TextStyle(color: Colors.white54),
                        ),
                      ],
                    ),
                  );
                }
                
                if (mapProvider.searchError != null) {
                  return Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colors.cardDark,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colors.brushedSteel),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(Icons.search_off, color: colors.silver, size: 18),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                mapProvider.searchError!,
                                style: TextStyle(
                                  color: colors.silver, 
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                                textAlign: TextAlign.left,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }
                
                if (mapProvider.searchResults.isNotEmpty) {
                  return Container(
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: colors.cardDark,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colors.brushedSteel),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: mapProvider.searchResults.length,
                      separatorBuilder: (_, __) => Divider(color: colors.brushedSteel, height: 1),
                      itemBuilder: (context, index) {
                        final result = mapProvider.searchResults[index];
                        // Advisory only — flag results implausibly far from the
                        // search bias point. Never blocks selection.
                        final biasLat = mapProvider.searchBiasLat;
                        final biasLng = mapProvider.searchBiasLng;
                        final isFar = biasLat != null &&
                            biasLng != null &&
                            _distanceKm(
                                  biasLat,
                                  biasLng,
                                  result.lat,
                                  result.lng,
                                ) >
                                _kFarResultThresholdKm;
                        return ListTile(
                          title: Text(result.displayName, style: const TextStyle(color: Colors.white)),
                          subtitle: Text(result.address, style: TextStyle(color: colors.silver, fontSize: 12)),
                          trailing: isFar ? _buildFarResultBadge(colors) : null,
                          onTap: () {
                            setState(() {
                              _selectedLat = result.lat;
                              _selectedLng = result.lng;
                              _selectedAddress = result.address;
                              _isSettingSelectedValue = true;
                              _searchController.text = result.displayName;
                              _isSettingSelectedValue = false;
                            });
                            mapProvider.clearSearchResults();
                          },
                        );
                      },
                    ),
                  );
                }
                
                return const SizedBox.shrink();
              },
            ),
            
            if (_selectedLat != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.electricRed.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.electricRed.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.location_on, color: colors.electricRed, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Selected: $_selectedAddress",
                        style: TextStyle(color: colors.white, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            
            const SizedBox(height: 24),
            
            _buildLabel("LAG THRESHOLD (METERS)"),
            const SizedBox(height: 8),
            _buildTextField(
              controller: _lagController,
              hintText: "500",
              keyboardType: TextInputType.number,
            ),
            
            const SizedBox(height: 40),
            
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: journeyProvider.isLoading ? null : _onCreateJourney,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.electricRed,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: journeyProvider.isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        widget.isEdit ? "UPDATE JOURNEY" : "CREATE JOURNEY",
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    TextInputType keyboardType = TextInputType.text,
    void Function(String)? onChanged,
    Widget? suffixIcon,
  }) {
    final colors = Theme.of(context).tulinkColors;
    
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: colors.silver.withValues(alpha: 0.5)),
        filled: true,
        fillColor: colors.cardDark,
        suffixIcon: suffixIcon,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.brushedSteel),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.brushedSteel),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.electricRed),
        ),
      ),
    );
  }

  /// Distance threshold (km) beyond which a search result is flagged as far
  /// from the user's bias point. Advisory only — selection is never blocked.
  static const double _kFarResultThresholdKm = 300;

  /// Inline "Far from you" advisory badge for results far from the bias point.
  Widget _buildFarResultBadge(TulinkColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.electricRed.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.electricRed.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.public_off, size: 12, color: colors.electricRed),
          const SizedBox(width: 4),
          Text(
            'Far from you',
            style: TextStyle(
              color: colors.electricRed,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Great-circle distance in kilometres between two coordinates (haversine).
  double _distanceKm(double lat1, double lng1, double lat2, double lng2) {
    const earthRadiusKm = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180.0;
    final dLng = (lng2 - lng1) * math.pi / 180.0;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180.0) *
            math.cos(lat2 * math.pi / 180.0) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }
}

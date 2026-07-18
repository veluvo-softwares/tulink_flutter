import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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

  /// Null = start-now journey; set = scheduled journey (local time here,
  /// converted to UTC at the API boundary).
  DateTime? _scheduledFor;
  bool _autoStart = false;

  /// Debounce for the destination search — only query the backend after a brief
  /// typing pause (FIX-05) so per-keystroke overlapping requests stop producing
  /// the spurious "check your internet" card.
  Timer? _searchDebounce;

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
    _scheduledFor = journey.scheduledFor?.toLocal();
    _autoStart = journey.autoStart;
    
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
    _searchDebounce?.cancel();
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
        if (_scheduledFor != null)
          'scheduledFor': _scheduledFor!.toUtc().toIso8601String(),
        if (_scheduledFor != null) 'autoStart': _autoStart,
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
        scheduledFor: _scheduledFor,
        autoStart: _autoStart,
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
                if (_isSettingSelectedValue) return;
                // Clear selection when user types manually (FIX-10: editing a
                // confirmed destination invalidates its coordinates).
                if (_selectedLat != null) {
                  setState(() {
                    _selectedLat = null;
                    _selectedLng = null;
                    _selectedAddress = null;
                  });
                }
                // Debounce the search (FIX-05): reset the timer on each keystroke;
                // an empty field clears immediately (and cancels in-flight via the
                // provider's request-id guard).
                _searchDebounce?.cancel();
                if (value.trim().isEmpty) {
                  context.read<MapProvider>().clearSearchResults();
                  return;
                }
                _searchDebounce = Timer(
                  const Duration(milliseconds: 400),
                  () => context.read<MapProvider>().searchPlaces(value),
                );
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

            const SizedBox(height: 24),

            _buildLabel("START TIME"),
            const SizedBox(height: 8),
            _buildScheduleSection(colors),

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

  /// "Start now" vs "Schedule for later" chooser. A scheduled journey keeps
  /// the normal lobby (invite/accept) flow; the backend reminds everyone and
  /// starts (or nudges the leader) at the chosen instant.
  Widget _buildScheduleSection(TulinkColors colors) {
    final scheduled = _scheduledFor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: _pickSchedule,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.cardDark,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: scheduled != null
                    ? colors.electricRed
                    : colors.brushedSteel,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  scheduled != null ? Icons.event : Icons.bolt,
                  color: scheduled != null ? colors.electricRed : colors.silver,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    scheduled != null
                        ? _formatSchedule(scheduled)
                        : 'Starts now — tap to schedule for later',
                    style: TextStyle(
                      color: scheduled != null ? Colors.white : colors.silver,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (scheduled != null)
                  IconButton(
                    icon: Icon(Icons.close, color: colors.silver, size: 18),
                    tooltip: 'Clear schedule (start now)',
                    onPressed: () => setState(() {
                      _scheduledFor = null;
                      _autoStart = false;
                    }),
                  ),
              ],
            ),
          ),
        ),
        if (scheduled != null)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Start automatically',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
            subtitle: Text(
              'Everyone is navigated to the map at the scheduled time',
              style: TextStyle(color: colors.silver, fontSize: 12),
            ),
            activeThumbColor: colors.electricRed,
            value: _autoStart,
            onChanged: (value) => setState(() => _autoStart = value),
          ),
      ],
    );
  }

  Future<void> _pickSchedule() async {
    final now = DateTime.now();
    final initial = _scheduledFor ?? now.add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 60)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;

    final picked = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    // Mirror the backend bound so the user hears about it before submitting.
    if (picked.isBefore(DateTime.now().add(const Duration(minutes: 5)))) {
      context.showErrorToast(
        'Scheduled time must be at least 5 minutes from now',
      );
      return;
    }
    setState(() => _scheduledFor = picked);
  }

  String _formatSchedule(DateTime when) {
    final formatted = DateFormat('EEE, MMM d • HH:mm').format(when);
    return 'Scheduled: $formatted';
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

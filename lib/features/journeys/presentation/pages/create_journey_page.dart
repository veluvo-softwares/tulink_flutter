import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/tulink_colors.dart';
import '../providers/journey_provider.dart';

class CreateJourneyPage extends StatefulWidget {
  const CreateJourneyPage({super.key});

  static const String routeName = '/create-journey';

  @override
  State<CreateJourneyPage> createState() => _CreateJourneyPageState();
}

class _CreateJourneyPageState extends State<CreateJourneyPage> {
  final _nameController = TextEditingController();
  final _searchController = TextEditingController();
  final _lagController = TextEditingController(text: '500');
  
  double? _selectedLat;
  double? _selectedLng;
  String? _selectedAddress;

  @override
  void dispose() {
    _nameController.dispose();
    _searchController.dispose();
    _lagController.dispose();
    super.dispose();
  }

  void _onCreateJourney() async {
    if (_nameController.text.isEmpty || _selectedLat == null || _selectedLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields and select a destination')),
      );
      return;
    }

    final success = await context.read<JourneyProvider>().createJourney(
      name: _nameController.text,
      latitude: _selectedLat!,
      longitude: _selectedLng!,
      destinationAddress: _selectedAddress ?? '',
      lagThresholdMeters: int.tryParse(_lagController.text) ?? 500,
    );

    if (success && mounted) {
      Navigator.of(context).pop();
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
        title: const Text('CREATE JOURNEY'),
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
              onChanged: (value) => journeyProvider.searchLocations(value),
              suffixIcon: const Icon(Icons.search, color: Colors.white54),
            ),
            
            if (journeyProvider.searchResults.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: colors.cardDark,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.brushedSteel),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: journeyProvider.searchResults.length,
                  separatorBuilder: (_, __) => Divider(color: colors.brushedSteel, height: 1),
                  itemBuilder: (context, index) {
                    final result = journeyProvider.searchResults[index];
                    return ListTile(
                      title: Text(result.name, style: const TextStyle(color: Colors.white)),
                      subtitle: Text(result.address, style: TextStyle(color: colors.silver, fontSize: 12)),
                      onTap: () {
                        setState(() {
                          _selectedLat = result.latitude;
                          _selectedLng = result.longitude;
                          _selectedAddress = result.address;
                          _searchController.text = result.name;
                        });
                        journeyProvider.clearSearchResults();
                      },
                    );
                  },
                ),
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
                    : const Text(
                        "CREATE JOURNEY",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
              ),
            ),
            
            if (journeyProvider.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Text(
                  journeyProvider.error!,
                  style: TextStyle(color: colors.electricRed),
                  textAlign: TextAlign.center,
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
    Function(String)? onChanged,
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
}

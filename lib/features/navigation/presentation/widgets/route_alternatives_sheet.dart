import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../domain/entities/directions_route.dart';
import '../../../../core/theme/tulink_colors.dart';

/// Bottom sheet for displaying and selecting route alternatives
class RouteAlternativesSheet extends StatelessWidget {
  const RouteAlternativesSheet({
    super.key,
    required this.routes,
    required this.onRouteSelected,
    this.selectedRouteIndex = 0,
    this.onClose,
  });

  final List<DirectionsRoute> routes;
  final Function(DirectionsRoute route, int index) onRouteSelected;
  final int selectedRouteIndex;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<TulinkColors>()!;
    
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: BoxDecoration(
        color: colors.carbonBlack,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: colors.electricRed.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: colors.silver.withOpacity(0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Choose Route',
                    style: GoogleFonts.poppins(
                      color: colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (onClose != null)
                  IconButton(
                    onPressed: onClose,
                    icon: Icon(
                      Icons.close,
                      color: colors.silver,
                    ),
                  ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Route list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: routes.length,
              itemBuilder: (context, index) {
                final route = routes[index];
                final isSelected = index == selectedRouteIndex;
                final isPrimary = index == 0;
                
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: RouteAlternativeCard(
                    route: route,
                    isSelected: isSelected,
                    isPrimary: isPrimary,
                    routeLabel: _getRouteLabel(index),
                    onTap: () => onRouteSelected(route, index),
                  ),
                );
              },
            ),
          ),
          
          // Bottom padding
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  String _getRouteLabel(int index) {
    switch (index) {
      case 0:
        return 'Fastest';
      case 1:
        return 'Alternative 1';
      case 2:
        return 'Alternative 2';
      default:
        return 'Route ${index + 1}';
    }
  }
}

/// Card widget for individual route alternative
class RouteAlternativeCard extends StatelessWidget {
  const RouteAlternativeCard({
    super.key,
    required this.route,
    required this.isSelected,
    required this.isPrimary,
    required this.routeLabel,
    required this.onTap,
  });

  final DirectionsRoute route;
  final bool isSelected;
  final bool isPrimary;
  final String routeLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<TulinkColors>()!;
    
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected 
              ? colors.electricRed.withOpacity(0.1)
              : colors.cardDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected 
                ? colors.electricRed
                : colors.silver.withOpacity(0.3),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: colors.electricRed.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Route header
            Row(
              children: [
                // Route indicator
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: isSelected ? colors.electricRed : colors.silver,
                    shape: BoxShape.circle,
                  ),
                  child: isSelected
                      ? Icon(
                          Icons.check,
                          color: colors.carbonBlack,
                          size: 14,
                        )
                      : null,
                ),
                
                const SizedBox(width: 12),
                
                // Route label
                Expanded(
                  child: Text(
                    routeLabel,
                    style: GoogleFonts.poppins(
                      color: isSelected ? colors.electricRed : colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                
                // Primary route badge
                if (isPrimary)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: colors.electricRed.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'RECOMMENDED',
                      style: GoogleFonts.poppins(
                        color: colors.electricRed,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Route stats
            Row(
              children: [
                // Duration
                _RouteStatItem(
                  icon: Icons.access_time,
                  label: 'Duration',
                  value: route.formattedDuration,
                  colors: colors,
                ),
                
                const SizedBox(width: 24),
                
                // Distance
                _RouteStatItem(
                  icon: Icons.straighten,
                  label: 'Distance',
                  value: route.formattedDistance,
                  colors: colors,
                ),
                
                const SizedBox(width: 24),
                
                // Arrival time
                _RouteStatItem(
                  icon: Icons.flag,
                  label: 'Arrival',
                  value: route.formattedArrivalTime,
                  colors: colors,
                ),
              ],
            ),
            
            // Traffic conditions (if available)
            if (route.legs != null && route.legs!.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildTrafficIndicator(colors),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTrafficIndicator(TulinkColors colors) {
    // Simplified traffic indicator
    // In a real implementation, you'd parse traffic data from the route
    return Row(
      children: [
        Icon(
          Icons.traffic,
          color: colors.silver,
          size: 16,
        ),
        const SizedBox(width: 8),
        Text(
          'Light traffic conditions',
          style: GoogleFonts.poppins(
            color: colors.silver,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

/// Widget for displaying individual route statistics
class _RouteStatItem extends StatelessWidget {
  const _RouteStatItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.colors,
  });

  final IconData icon;
  final String label;
  final String value;
  final TulinkColors colors;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: colors.silver,
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: GoogleFonts.poppins(
                  color: colors.silver,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.poppins(
              color: colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
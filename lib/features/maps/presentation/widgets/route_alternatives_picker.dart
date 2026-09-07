import 'package:flutter/material.dart';

import 'package:tulink_flutter/core/theme/tulink_colors.dart';
import 'package:tulink_flutter/features/maps/data/models/route_result_model.dart';

/// A horizontally scrollable set of route choices for pre-departure planning.
class RouteAlternativesPicker extends StatelessWidget {
  const RouteAlternativesPicker({
    required this.routes,
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  /// The primary route followed by any alternatives.
  final List<RouteResultModel> routes;

  /// The route currently highlighted on the map.
  final int selectedIndex;

  /// Called when the user chooses a route card.
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    if (routes.isEmpty) return const SizedBox.shrink();
    final fastestSeconds = routes
        .map((route) => route.durationSeconds)
        .reduce((a, b) => a < b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Choose your route',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${routes.length} option${routes.length == 1 ? '' : 's'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: routes.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) => SizedBox(
              width: routes.length == 1 ? 280 : 240,
              child: _RouteOptionCard(
                route: routes[index],
                index: index,
                selected: index == selectedIndex,
                fastestSeconds: fastestSeconds,
                onTap: () => onSelected(index),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RouteOptionCard extends StatelessWidget {
  const _RouteOptionCard({
    required this.route,
    required this.index,
    required this.selected,
    required this.fastestSeconds,
    required this.onTap,
  });

  final RouteResultModel route;
  final int index;
  final bool selected;
  final double fastestSeconds;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;
    final isFastest = (route.durationSeconds - fastestSeconds).abs() < 1;
    final delayMinutes = ((route.durationSeconds - fastestSeconds) / 60).ceil();
    final label = isFastest ? 'Fastest' : 'Route ${index + 1}';

    return Semantics(
      button: true,
      selected: selected,
      label:
          '$label, ${_duration(route.durationSeconds)}, '
          '${_distance(route.distanceMetres)}',
      child: Material(
        color: selected
            ? colors.routeTeal.withValues(alpha: .12)
            : colors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: Key('route-option-$index'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 11, 12, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? colors.routeTeal : colors.divider,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? colors.routeTeal : colors.muted,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.ink,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (!isFastest && delayMinutes > 0) ...[
                            const SizedBox(width: 6),
                            Text(
                              '+$delayMinutes min',
                              style: TextStyle(
                                color: colors.muted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _duration(route.durationSeconds),
                        style: TextStyle(
                          color: selected ? colors.routeTeal : colors.ink,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${_distance(route.distanceMetres)} • '
                        'arrive ${_arrival(route.durationSeconds)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _duration(double seconds) {
  final minutes = (seconds / 60).round();
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  return remainder == 0 ? '$hours hr' : '$hours hr $remainder min';
}

String _distance(double metres) {
  if (metres < 1000) return '${metres.round()} m';
  return '${(metres / 1000).toStringAsFixed(metres >= 10000 ? 0 : 1)} km';
}

String _arrival(double seconds) {
  final arrival = DateTime.now().add(Duration(seconds: seconds.round()));
  final hour = arrival.hour.toString().padLeft(2, '0');
  final minute = arrival.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

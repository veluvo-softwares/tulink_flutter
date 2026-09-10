import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../../../../core/services/location_service.dart';
import '../../../../core/theme/tulink_colors.dart';
import '../../../maps/data/datasources/route_remote_data_source.dart';
import '../../../maps/data/models/route_result_model.dart';
import '../../../maps/domain/entities/place_search_result.dart';
import '../../../maps/presentation/widgets/route_alternatives_picker.dart';
import '../../domain/entities/saved_route.dart';
import '../providers/saved_route_provider.dart';

enum SavedRouteLibraryCommand { plan, record }

class SavedRouteLibraryResult {
  const SavedRouteLibraryResult.use(this.route)
    : command = null,
      editRoute = null;
  const SavedRouteLibraryResult.command(this.command)
    : route = null,
      editRoute = null;
  const SavedRouteLibraryResult.edit(this.editRoute)
    : route = null,
      command = null;

  final SavedRoute? route;
  final SavedRouteLibraryCommand? command;
  final SavedRoute? editRoute;
}

class SavedRouteLibrarySheet extends StatefulWidget {
  const SavedRouteLibrarySheet({super.key, this.isLandscapePanel = false});

  final bool isLandscapePanel;

  @override
  State<SavedRouteLibrarySheet> createState() => _SavedRouteLibrarySheetState();
}

class _SavedRouteLibrarySheetState extends State<SavedRouteLibrarySheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SavedRouteProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SavedRouteProvider>();
    final colors = Theme.of(context).tulinkColors;
    return SafeArea(
      child: SizedBox(
        width: widget.isLandscapePanel ? 520 : null,
        height: widget.isLandscapePanel
            ? MediaQuery.sizeOf(context).height - 80
            : MediaQuery.sizeOf(context).height * .78,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Saved routes',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close saved routes',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              Text(
                'Plan reusable roads or record private tracks while driving.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(
                        context,
                        const SavedRouteLibraryResult.command(
                          SavedRouteLibraryCommand.plan,
                        ),
                      ),
                      icon: const Icon(Icons.alt_route_rounded),
                      label: const Text('Plan route'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(
                        context,
                        const SavedRouteLibraryResult.command(
                          SavedRouteLibraryCommand.record,
                        ),
                      ),
                      icon: const Icon(Icons.fiber_manual_record_rounded),
                      label: const Text('Record route'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (provider.isLoading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (provider.error != null && provider.routes.isEmpty)
                Expanded(
                  child: Center(
                    child: TextButton.icon(
                      onPressed: provider.load,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(provider.error!),
                    ),
                  ),
                )
              else if (provider.routes.isEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.route_outlined,
                          size: 48,
                          color: colors.muted,
                        ),
                        const SizedBox(height: 12),
                        const Text('No saved routes yet'),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: provider.load,
                    child: ListView.separated(
                      itemCount: provider.routes.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final route = provider.routes[index];
                        return _SavedRouteCard(
                          route: route,
                          onUse: () => Navigator.pop(
                            context,
                            SavedRouteLibraryResult.use(route),
                          ),
                          onArchive: route.canEdit
                              ? () => provider.archive(route.id)
                              : null,
                          onEdit: route.canEdit
                              ? () => Navigator.pop(
                                  context,
                                  SavedRouteLibraryResult.edit(route),
                                )
                              : null,
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SavedRouteCard extends StatelessWidget {
  const _SavedRouteCard({
    required this.route,
    required this.onUse,
    this.onArchive,
    this.onEdit,
  });

  final SavedRoute route;
  final VoidCallback onUse;
  final VoidCallback? onArchive;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;
    final kilometres = route.distanceMetres / 1000;
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onUse,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: colors.routeTeal.withValues(alpha: .14),
                foregroundColor: colors.routeTeal,
                child: Icon(
                  route.source == SavedRouteSource.recorded
                      ? Icons.gps_fixed_rounded
                      : Icons.alt_route_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      route.name,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${kilometres.toStringAsFixed(kilometres >= 10 ? 0 : 1)} km'
                      ' • ${route.source.name}',
                      style: TextStyle(color: colors.muted),
                    ),
                  ],
                ),
              ),
              if (onEdit != null)
                IconButton(
                  tooltip: 'Edit saved route',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
              if (onArchive != null)
                IconButton(
                  tooltip: 'Remove saved route',
                  onPressed: onArchive,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class SavedRouteComposerSheet extends StatefulWidget {
  const SavedRouteComposerSheet({
    required this.mode,
    required this.routeDataSource,
    required this.locationService,
    required this.searchPlace,
    required this.preview,
    super.key,
    this.initialRoute,
    this.isLandscapePanel = false,
  });

  final SavedRouteLibraryCommand mode;
  final RouteRemoteDataSource routeDataSource;
  final LocationService locationService;
  final Future<PlaceSearchResult?> Function() searchPlace;
  final Future<void> Function(RouteResultModel route) preview;
  final SavedRoute? initialRoute;
  final bool isLandscapePanel;

  @override
  State<SavedRouteComposerSheet> createState() =>
      _SavedRouteComposerSheetState();
}

class _SavedRouteComposerSheetState extends State<SavedRouteComposerSheet> {
  final _nameController = TextEditingController();
  final _waypoints = <SavedRouteWaypoint>[];
  final _recordedGeometry = <List<double>>[];
  final _stopwatch = Stopwatch();
  StreamSubscription<Position>? _positionSubscription;
  List<RouteResultModel> _routeOptions = const [];
  int _selectedRouteIndex = 0;
  bool _loadingPreview = false;
  bool _recording = false;
  double _recordedBaseDurationSeconds = 0;
  String? _message;

  bool get _isPlan => widget.mode == SavedRouteLibraryCommand.plan;

  @override
  void initState() {
    super.initState();
    final route = widget.initialRoute;
    if (route == null) return;
    _nameController.text = route.name;
    _waypoints.addAll(route.waypoints);
    if (!_isPlan) {
      _recordedGeometry.addAll(route.geometry);
      _recordedBaseDurationSeconds = route.durationSeconds ?? 0;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || route.geometry.length < 2) return;
      unawaited(widget.preview(_modelFromSavedRoute(route)));
    });
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _stopwatch.stop();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _addCurrentLocation() async {
    final position = await widget.locationService.getCurrentPosition();
    if (!mounted) return;
    if (position == null) {
      setState(() => _message = 'A GPS fix is not available yet.');
      return;
    }
    setState(() {
      _waypoints.add(
        SavedRouteWaypoint(
          latitude: position.latitude,
          longitude: position.longitude,
          name: _waypoints.isEmpty ? 'Current location' : 'Waypoint',
        ),
      );
      _routeOptions = const [];
      _message = null;
    });
  }

  Future<void> _addPlace() async {
    final place = await widget.searchPlace();
    if (place == null || !mounted) return;
    setState(() {
      _waypoints.add(
        SavedRouteWaypoint(
          latitude: place.lat,
          longitude: place.lng,
          name: place.displayName,
        ),
      );
      _routeOptions = const [];
      _message = null;
    });
  }

  Future<void> _buildPreview() async {
    if (_waypoints.length < 2) {
      setState(() => _message = 'Add at least a start and destination.');
      return;
    }
    setState(() {
      _loadingPreview = true;
      _message = null;
    });
    final route = await widget.routeDataSource.getRouteThrough(
      _waypoints
          .map(
            (point) => (latitude: point.latitude, longitude: point.longitude),
          )
          .toList(growable: false),
    );
    if (!mounted) return;
    if (route == null) {
      setState(() {
        _loadingPreview = false;
        _message = 'No drivable route was found through these points.';
      });
      return;
    }
    final options = [route, ...route.alternates];
    setState(() {
      _routeOptions = options;
      _selectedRouteIndex = 0;
      _loadingPreview = false;
    });
    await widget.preview(options.first);
  }

  Future<void> _selectRoute(int index) async {
    setState(() => _selectedRouteIndex = index);
    await widget.preview(_routeOptions[index]);
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      await _positionSubscription?.cancel();
      _positionSubscription = null;
      _stopwatch.stop();
      if (mounted) setState(() => _recording = false);
      return;
    }
    _stopwatch.start();
    setState(() {
      _recording = true;
      _message = null;
    });
    _positionSubscription = widget.locationService
        .getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 5,
          ),
        )
        .listen(_capturePosition, onError: (_) => _pauseAfterError());
  }

  void _pauseAfterError() {
    _stopwatch.stop();
    if (mounted) {
      setState(() {
        _recording = false;
        _message = 'GPS recording paused. Check location access.';
      });
    }
  }

  void _capturePosition(Position position) {
    if (position.accuracy > 60) return;
    final point = <double>[position.longitude, position.latitude];
    if (_recordedGeometry.isNotEmpty) {
      final previous = _recordedGeometry.last;
      final distance = Geolocator.distanceBetween(
        previous[1],
        previous[0],
        point[1],
        point[0],
      );
      if (distance < 3) return;
    }
    setState(() => _recordedGeometry.add(point));
    unawaited(
      widget.preview(
        RouteResultModel(
          coordinates: List.unmodifiable(_recordedGeometry),
          distanceMetres: _recordedDistance,
          durationSeconds: _stopwatch.elapsedMilliseconds / 1000,
          steps: const [],
        ),
      ),
    );
  }

  double get _recordedDistance {
    var distance = 0.0;
    for (var index = 1; index < _recordedGeometry.length; index++) {
      final previous = _recordedGeometry[index - 1];
      final current = _recordedGeometry[index];
      distance += Geolocator.distanceBetween(
        previous[1],
        previous[0],
        current[1],
        current[0],
      );
    }
    return distance;
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.length < 2) {
      setState(() => _message = 'Give this route a name.');
      return;
    }
    if (_isPlan && _routeOptions.isEmpty) {
      setState(() => _message = 'Preview the route before saving it.');
      return;
    }
    if (!_isPlan && _recordedGeometry.length < 2) {
      setState(() => _message = 'Record more of the route before saving.');
      return;
    }
    await _positionSubscription?.cancel();
    _stopwatch.stop();
    if (!mounted) return;
    final provider = context.read<SavedRouteProvider>();
    final recordedWaypoints = _recordedGeometry.length < 2
        ? const <SavedRouteWaypoint>[]
        : [
            SavedRouteWaypoint(
              latitude: _recordedGeometry.first[1],
              longitude: _recordedGeometry.first[0],
              name: 'Start',
            ),
            SavedRouteWaypoint(
              latitude: _recordedGeometry.last[1],
              longitude: _recordedGeometry.last[0],
              name: 'Finish',
            ),
          ];
    final source = _isPlan
        ? SavedRouteSource.computed
        : SavedRouteSource.recorded;
    final waypoints = _isPlan ? _waypoints : recordedWaypoints;
    final geometry = _isPlan ? null : _recordedGeometry;
    final duration = _isPlan
        ? null
        : _recordedBaseDurationSeconds + _stopwatch.elapsedMilliseconds / 1000;
    final existing = widget.initialRoute;
    final saved = existing == null
        ? await provider.create(
            name: name,
            source: source,
            waypoints: waypoints,
            geometry: geometry,
            routeIndex: _selectedRouteIndex,
            recordedDurationSeconds: duration,
          )
        : await provider.update(
            existing: existing,
            name: name,
            source: source,
            waypoints: waypoints,
            geometry: geometry,
            routeIndex: _selectedRouteIndex,
            recordedDurationSeconds: duration,
          );
    if (!mounted) return;
    if (saved == null) {
      setState(() => _message = provider.error ?? 'Could not save route.');
      return;
    }
    Navigator.pop(context, saved);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SavedRouteProvider>();
    final colors = Theme.of(context).tulinkColors;
    return SafeArea(
      child: SizedBox(
        width: widget.isLandscapePanel ? 520 : null,
        height: widget.isLandscapePanel
            ? MediaQuery.sizeOf(context).height - 80
            : MediaQuery.sizeOf(context).height * .82,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.initialRoute != null
                          ? 'Edit route'
                          : _isPlan
                          ? 'Plan a route'
                          : 'Record a route',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Route name',
                  hintText: 'Airstrip transfer',
                ),
              ),
              const SizedBox(height: 14),
              if (_isPlan) ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _addCurrentLocation,
                        icon: const Icon(Icons.my_location_rounded),
                        label: const Text('Current location'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _addPlace,
                        icon: const Icon(Icons.add_location_alt_outlined),
                        label: const Text('Add place'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ReorderableListView.builder(
                    itemCount: _waypoints.length,
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex--;
                        final point = _waypoints.removeAt(oldIndex);
                        _waypoints.insert(newIndex, point);
                        _routeOptions = const [];
                      });
                    },
                    itemBuilder: (context, index) {
                      final point = _waypoints[index];
                      return ListTile(
                        key: ValueKey(
                          '${point.latitude}:${point.longitude}:$index',
                        ),
                        leading: CircleAvatar(
                          backgroundColor: colors.routeTeal.withValues(
                            alpha: .12,
                          ),
                          child: Text('${index + 1}'),
                        ),
                        title: Text(point.name ?? 'Waypoint ${index + 1}'),
                        subtitle: Text(
                          '${point.latitude.toStringAsFixed(5)}, '
                          '${point.longitude.toStringAsFixed(5)}',
                        ),
                        trailing: IconButton(
                          onPressed: () => setState(() {
                            _waypoints.removeAt(index);
                            _routeOptions = const [];
                          }),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      );
                    },
                  ),
                ),
                if (_routeOptions.isNotEmpty)
                  RouteAlternativesPicker(
                    routes: _routeOptions,
                    selectedIndex: _selectedRouteIndex,
                    onSelected: (index) => unawaited(_selectRoute(index)),
                  ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _loadingPreview ? null : _buildPreview,
                  icon: _loadingPreview
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.route_rounded),
                  label: const Text('Preview route options'),
                ),
              ] else ...[
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _recording
                              ? Icons.gps_fixed_rounded
                              : Icons.route_outlined,
                          size: 58,
                          color: _recording ? colors.electricRed : colors.muted,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _recording
                              ? 'Recording your track'
                              : 'Ready to record',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${(_recordedDistance / 1000).toStringAsFixed(2)} km'
                          ' • ${_recordedGeometry.length} GPS points',
                        ),
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: _toggleRecording,
                          icon: Icon(
                            _recording
                                ? Icons.pause_rounded
                                : Icons.fiber_manual_record_rounded,
                          ),
                          label: Text(_recording ? 'Pause' : 'Start recording'),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Start before moving and review only after stopping. '
                          'Drive normally—slow driving is not required.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.muted),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (_message != null) ...[
                const SizedBox(height: 8),
                Text(_message!, style: TextStyle(color: colors.electricRed)),
              ],
              const SizedBox(height: 10),
              FilledButton(
                onPressed: provider.isSaving ? null : _save,
                child: provider.isSaving
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save route'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

RouteResultModel _modelFromSavedRoute(SavedRoute route) => RouteResultModel(
  coordinates: route.geometry,
  distanceMetres: route.distanceMetres,
  durationSeconds: route.durationSeconds ?? 0,
  steps: route.steps
      .map(
        (step) => RouteStepModel(
          instruction: step.instruction,
          distanceMetres: step.distanceMetres,
          maneuver: step.maneuver,
        ),
      )
      .toList(growable: false),
);

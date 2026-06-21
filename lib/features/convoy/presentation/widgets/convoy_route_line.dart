import 'dart:convert';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import '../../domain/entities/convoy_snapshot.dart';
import '../../domain/entities/member_position.dart';

class ConvoyRouteLine {
  static const String _membersSourceId = 'convoy-members-source';

  /// Render convoy member markers from a [ConvoySnapshot].
  ///
  /// Builds each feature from the member's raw (authoritative) position and
  /// delegates to [renderMemberMarkers], which creates the source + layers on
  /// first render and updates the source data in place afterwards.
  static Future<void> addConvoyMarkers(
    MapboxMap mapboxMap,
    ConvoySnapshot snapshot,
    String currentUserId,
  ) async {
    // Bail if destination coordinates are invalid (0,0 fallback)
    if (snapshot.destination.latitude == 0.0 &&
        snapshot.destination.longitude == 0.0) {
      print('⚠️ Skipping convoy rendering — destination coordinates are (0,0)');
      return;
    }

    // Current user is already excluded by the provider's display snapshot.
    final members = snapshot.members.values.toList();
    final coordinates = <List<double>>[
      for (final member in members) [member.longitude, member.latitude],
    ];

    await renderMemberMarkers(mapboxMap, members, coordinates);
  }

  /// Render [members] at the given [coordinates] (each `[lng, lat]`, parallel
  /// to [members]).
  ///
  /// On first render (source absent) the GeoJSON source and the three layers
  /// are added once. On every subsequent render only the source `data` is
  /// updated in place via `setStyleSourceProperty`, so the layers are never
  /// torn down — eliminating the blank-frame flicker that made peers "poof".
  ///
  /// This is the single render path shared by snapshot-driven updates and the
  /// interpolation ticker, so colour/status changes (driven by the per-feature
  /// `status` property) flow through here without rebuilding layers.
  static Future<void> renderMemberMarkers(
    MapboxMap mapboxMap,
    List<MemberPosition> members,
    List<List<double>> coordinates,
  ) async {
    try {
      final geoJson = _buildMembersGeoJson(members, coordinates);

      final sourceExists =
          await mapboxMap.style.styleSourceExists(_membersSourceId);
      if (sourceExists) {
        // In-place update — no layer teardown, no blank frame.
        await mapboxMap.style.setStyleSourceProperty(
          _membersSourceId,
          'data',
          geoJson,
        );
        return;
      }

      await mapboxMap.style.addSource(GeoJsonSource(
        id: _membersSourceId,
        data: geoJson,
      ));
      await _addMemberMarkersLayer(mapboxMap);

      // Destination marker is drawn by _drawDestinationPin in
      // tulink_map_screen.dart from static Journey data — no duplicate
      // destination layer is needed here.

      print('✅ Convoy member markers added');
    } catch (e) {
      print('❌ Failed to render convoy markers: $e');
    }
  }

  /// Remove convoy markers from the map
  static Future<void> removeConvoyMarkers(MapboxMap mapboxMap) async {
    try {
      await mapboxMap.style.removeStyleLayer('convoy-members-label-layer');
    } catch (e) {
      // Ignore errors for non-existent layers/sources
    }
    try {
      await mapboxMap.style.removeStyleLayer('convoy-members-layer');
    } catch (e) {
      // Ignore errors for non-existent layers/sources
    }
    try {
      await mapboxMap.style.removeStyleLayer('convoy-members-heading-layer');
    } catch (e) {
      // Ignore errors for non-existent layers/sources
    }
    try {
      await mapboxMap.style.removeStyleSource(_membersSourceId);
    } catch (e) {
      // Ignore errors for non-existent layers/sources
    }
  }

  /// Build the members `FeatureCollection` JSON from [members] and parallel
  /// [coordinates] (each `[lng, lat]`). Geometry comes from [coordinates] (so
  /// the interpolation ticker can supply display-only projected positions)
  /// while all properties come from the authoritative [MemberPosition].
  static String _buildMembersGeoJson(
    List<MemberPosition> members,
    List<List<double>> coordinates,
  ) {
    final features = <Map<String, dynamic>>[];

    for (int i = 0; i < members.length; i++) {
      final member = members[i];
      final coordinate = i < coordinates.length
          ? coordinates[i]
          : <double>[member.longitude, member.latitude];
      features.add({
        'type': 'Feature',
        'properties': {
          'userId': member.userId,
          'userIndex': i % 5,
          'isMoving': member.isMoving,
          'speed': member.speed ?? 0.0,
          'initials': _initialsForUser(member.userId),
          'heading': member.heading ?? 0.0,
          'status': member.memberStatus,
        },
        'geometry': {
          'type': 'Point',
          'coordinates': coordinate,
        },
      });
    }

    return jsonEncode({
      'type': 'FeatureCollection',
      'features': features,
    });
  }

  /// Extract 2-character initials from a userId. Falls back to a single
  /// letter if the userId is shorter. Real names should be threaded
  /// through here in a future iteration via a user-display-name lookup
  /// service; for now, the userId initials are the consistent identifier.
  static String _initialsForUser(String userId) {
    final clean = userId.trim();
    if (clean.length >= 2) return clean.substring(0, 2).toUpperCase();
    if (clean.isNotEmpty) return clean.substring(0, 1).toUpperCase();
    return '?';
  }

  /// Add member marker layers. Three layers stacked per member feature:
  /// heading arrow underneath, coloured dot in the middle, initials label
  /// on top.
  ///
  /// Colours are driven by each feature's `status` property using Mapbox
  /// match expressions, so a single layer renders five different colour
  /// states without needing five separate layers.
  static Future<void> _addMemberMarkersLayer(MapboxMap mapboxMap) async {
    // ── Heading arrow layer ──────────────────────────────────────────
    //
    // Rendered as a Mapbox built-in arrow icon, rotated by `heading`,
    // sitting just below the dot so its base is occluded and only the
    // tip pokes out as a directional indicator.
    try {
      await mapboxMap.style.addLayer(SymbolLayer(
        id: 'convoy-members-heading-layer',
        sourceId: _membersSourceId,
        iconImage: 'triangle-stroked-15',
        iconSize: 1.4,
        iconRotateExpression: ['get', 'heading'],
        iconRotationAlignment: IconRotationAlignment.MAP,
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
        iconOffset: [0.0, -1.8],
      ));
    } catch (e) {
      print('⚠️ Failed to add heading layer: $e');
    }

    // ── Member dot layer ─────────────────────────────────────────────
    //
    // circleColor is a match expression driven by each feature's `status`
    // property. Falls back to Electric Red for unknown statuses.
    try {
      await mapboxMap.style.addLayer(CircleLayer(
        id: 'convoy-members-layer',
        sourceId: _membersSourceId,
        circleRadius: 14.0,
        circleStrokeColor: 0xFFFFFFFF,
        circleStrokeWidth: 2.5,
        circleOpacity: 1.0,
        circleColorExpression: [
          'match',
          ['get', 'status'],
          'MOVING', '#38A169',
          'STOPPED', '#3182CE',
          'LAG', '#DD6B20',
          'ARRIVED', '#0D7C66',
          'OFFLINE', '#718096',
          '#E8002D',
        ],
      ));
    } catch (e) {
      print('⚠️ Failed to add members dot layer: $e');
    }

    // ── Initials label layer ─────────────────────────────────────────
    //
    // The initials sit centred on the dot.
    try {
      await mapboxMap.style.addLayer(SymbolLayer(
        id: 'convoy-members-label-layer',
        sourceId: _membersSourceId,
        textFieldExpression: ['get', 'initials'],
        textFont: ['DIN Pro Bold', 'Arial Unicode MS Bold'],
        textSize: 11.0,
        textColor: 0xFFFFFFFF,
        textHaloColor: 0xFF000000,
        textHaloWidth: 1.0,
        textAllowOverlap: true,
        textIgnorePlacement: true,
      ));
    } catch (e) {
      print('⚠️ Failed to add label layer: $e');
    }
  }
}

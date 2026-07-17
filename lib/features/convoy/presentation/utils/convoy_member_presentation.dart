import 'package:flutter/material.dart';

import '../../../journeys/domain/entities/journey.dart';

/// Stable, journey-scoped visual identity for a convoy participant.
class ConvoyMemberPresentation {
  const ConvoyMemberPresentation({
    required this.userId,
    required this.displayName,
    required this.initials,
    required this.color,
  });

  final String userId;
  final String displayName;
  final String initials;
  final Color color;

  static const List<Color> palette = <Color>[
    Color(0xFFE8002D), // Tu-Link red — leader
    Color(0xFF3182CE),
    Color(0xFF38A169),
    Color(0xFFDD6B20),
    Color(0xFF805AD5),
    Color(0xFF00A6A6),
    Color(0xFFD53F8C),
    Color(0xFF718096),
  ];

  static Map<String, ConvoyMemberPresentation> forJourney(
    Journey journey, {
    Iterable<String> additionalUserIds = const <String>[],
    String? currentUserId,
    String? currentUserName,
  }) {
    final names = <String, String>{
      for (final participant in journey.participants ?? const <Participant>[])
        participant.userId: _usableName(
          participant.displayName,
          participant.userId,
        ),
    };
    if (currentUserId != null && currentUserId.isNotEmpty) {
      final cleanCurrentName = currentUserName?.trim();
      if (cleanCurrentName != null && cleanCurrentName.isNotEmpty) {
        names[currentUserId] = cleanCurrentName;
      } else {
        names.putIfAbsent(currentUserId, () => currentUserId);
      }
    }
    for (final userId in additionalUserIds) {
      names.putIfAbsent(userId, () => userId);
    }

    final orderedIds = names.keys.toList()
      ..sort((a, b) {
        if (a == journey.leaderId) return -1;
        if (b == journey.leaderId) return 1;
        return a.compareTo(b);
      });

    return <String, ConvoyMemberPresentation>{
      for (var index = 0; index < orderedIds.length; index++)
        orderedIds[index]: ConvoyMemberPresentation(
          userId: orderedIds[index],
          displayName: names[orderedIds[index]]!,
          initials: initialsFor(names[orderedIds[index]]!),
          color: palette[index % palette.length],
        ),
    };
  }

  static String initialsFor(String value) {
    final words = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.length >= 2) {
      return '${words.first[0]}${words.last[0]}'.toUpperCase();
    }
    if (words.isEmpty) return '?';
    final word = words.first;
    return word.substring(0, word.length.clamp(1, 2)).toUpperCase();
  }

  static String _usableName(String? name, String fallback) {
    final clean = name?.trim();
    return clean == null || clean.isEmpty ? fallback : clean;
  }
}

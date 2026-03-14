import 'package:flutter/material.dart';

/// Utility class for managing user pin display and colors
class UserPinUtils {
  /// Extract initials from a display name
  /// Examples:
  /// - "John Doe" -> "JD"
  /// - "Mary Jane Watson" -> "MJ" (first two words)
  /// - "Prince" -> "P"
  /// - "" -> "?"
  static String extractInitials(String displayName) {
    if (displayName.trim().isEmpty) {
      return '?';
    }
    
    final words = displayName.trim().split(RegExp(r'\s+'));
    
    if (words.length == 1) {
      // Single word - take first character
      return words[0][0].toUpperCase();
    } else {
      // Multiple words - take first letter of first two words
      return (words[0][0] + words[1][0]).toUpperCase();
    }
  }
  
  /// Get color for user based on their position in the journey
  /// Colors cycle through a predefined list
  static Color getUserColor(int userIndex) {
    final colors = [
      const Color(0xFFE53E3E), // Red
      const Color(0xFF38A169), // Green  
      const Color(0xFFDD6B20), // Orange
      const Color(0xFF3182CE), // Blue
      const Color(0xFF805AD5), // Purple
      const Color(0xFFD69E2E), // Yellow
      const Color(0xFFE53E3E), // Pink (reusing red variant)
      const Color(0xFF319795), // Teal
    ];
    
    return colors[userIndex % colors.length];
  }
  
  /// Get a lighter version of the user color for backgrounds
  static Color getUserColorLight(int userIndex) {
    return getUserColor(userIndex).withValues(alpha: 0.2);
  }
  
  /// Get a darker version of the user color for borders/outlines
  static Color getUserColorDark(int userIndex) {
    final baseColor = getUserColor(userIndex);
    return Color.fromRGBO(
      (baseColor.r * 255.0 * 0.8).round().clamp(0, 255),
      (baseColor.g * 255.0 * 0.8).round().clamp(0, 255), 
      (baseColor.b * 255.0 * 0.8).round().clamp(0, 255),
      1,
    );
  }
  
  /// Predefined color names for debugging/display
  static String getColorName(int userIndex) {
    final colorNames = [
      'Red',
      'Green', 
      'Orange',
      'Blue',
      'Purple',
      'Yellow',
      'Pink',
      'Teal',
    ];
    
    return colorNames[userIndex % colorNames.length];
  }
}
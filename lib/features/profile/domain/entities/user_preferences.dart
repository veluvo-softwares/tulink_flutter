/// Navigation preferences synchronized for the authenticated user.
class UserPreferences {
  /// Creates a complete preference snapshot.
  const UserPreferences({
    required this.followLeaderByDefault,
    required this.voiceNavigationEnabled,
  });

  /// Whether convoy followers use the leader's selected route by default.
  final bool followLeaderByDefault;

  /// Whether the device should announce turn-by-turn instructions.
  final bool voiceNavigationEnabled;
}

import 'package:flutter/foundation.dart';
import 'package:tulink_flutter/core/common/result.dart';
import 'package:tulink_flutter/features/invites/domain/entities/journey_invitation.dart';
import 'package:tulink_flutter/features/invites/domain/entities/user_search_result.dart';
import 'package:tulink_flutter/features/invites/domain/usecases/invite_usecases.dart';

class InviteProvider extends ChangeNotifier {
  final SearchUsers searchUsersUseCase;
  final SendInvite sendInviteUseCase;
  final GetInvitations getInvitationsUseCase;
  final AcceptInvitation acceptInvitationUseCase;
  final DeclineInvitation declineInvitationUseCase;

  InviteProvider({
    required this.searchUsersUseCase,
    required this.sendInviteUseCase,
    required this.getInvitationsUseCase,
    required this.acceptInvitationUseCase,
    required this.declineInvitationUseCase,
  });

  // Search state
  List<UserSearchResult> _searchResults = [];
  List<UserSearchResult> get searchResults => _searchResults;

  bool _isSearching = false;
  bool get isSearching => _isSearching;

  String? _searchError;
  String? get searchError => _searchError;

  // Tracks uids invited in the current session
  final Set<String> _invitedUserIds = {};
  Set<String> get invitedUserIds => _invitedUserIds;

  bool _isInviting = false;
  bool get isInviting => _isInviting;

  String? _inviteError;
  String? get inviteError => _inviteError;

  // Invitations state (invitee view)
  List<JourneyInvitation> _invitations = [];
  List<JourneyInvitation> get invitations => _invitations;

  bool _isLoadingInvitations = false;
  bool get isLoadingInvitations => _isLoadingInvitations;

  DateTime? _lastRefreshedAt;

  String? _invitationsError;
  String? get invitationsError => _invitationsError;

  // Accept state
  bool _isAccepting = false;
  bool get isAccepting => _isAccepting;

  String? _acceptError;
  String? get acceptError => _acceptError;

  bool _isDeclining = false;
  bool get isDeclining => _isDeclining;

  String? _declineError;
  String? get declineError => _declineError;

  // Tracks accepted journey ids in the current session
  final Set<String> _acceptedJourneyIds = {};
  Set<String> get acceptedJourneyIds => _acceptedJourneyIds;

  int get pendingInvitationCount => _invitations.length;

  Future<void> searchUsers(String query) async {
    _isSearching = true;
    _searchError = null;
    notifyListeners();

    final result = await searchUsersUseCase(query);

    if (result.isSuccess && result.data != null) {
      _searchResults = result.data!;
    } else {
      _searchError = result.failure?.message ?? 'Search failed';
      _searchResults = [];
    }

    _isSearching = false;
    notifyListeners();
  }

  void clearSearch() {
    _searchResults = [];
    _searchError = null;
    _isSearching = false;
    notifyListeners();
  }

  void resetInviteSession() {
    _invitedUserIds.clear();
    _inviteError = null;
    notifyListeners();
  }

  Future<bool> sendInvite({
    required String journeyId,
    required String invitedUserId,
  }) async {
    _isInviting = true;
    _inviteError = null;
    notifyListeners();

    final result = await sendInviteUseCase(
      journeyId: journeyId,
      invitedUserId: invitedUserId,
    );

    if (result.isSuccess) {
      _invitedUserIds.add(invitedUserId);
      _isInviting = false;
      notifyListeners();
      return true;
    } else {
      _inviteError = result.failure?.message ?? 'Failed to send invitation';
      _isInviting = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> fetchInvitations() async {
    _isLoadingInvitations = true;
    _invitationsError = null;
    notifyListeners();

    final result = await getInvitationsUseCase();

    if (result.isSuccess && result.data != null) {
      _invitations = result.data!;
    } else {
      _invitationsError =
          result.failure?.message ?? 'Failed to load invitations';
    }

    _isLoadingInvitations = false;
    _lastRefreshedAt = DateTime.now();
    notifyListeners();
  }

  /// Silently refresh invitations in the background without showing the
  /// loading indicator. Used by the home screen polling timer so the badge
  /// count updates automatically without causing a full-screen spinner.
  ///
  /// Debounced to at most once per 30 seconds to prevent rapid duplicate
  /// network calls from overlapping sources (timer + lifecycle + init).
  Future<void> refreshInvitationsSilently() async {
    if (_isLoadingInvitations) return;
    final now = DateTime.now();
    if (_lastRefreshedAt != null &&
        now.difference(_lastRefreshedAt!) < const Duration(seconds: 30)) {
      return;
    }
    final result = await getInvitationsUseCase();
    if (result.isSuccess && result.data != null) {
      _invitations = result.data!;
      _lastRefreshedAt = DateTime.now();
      notifyListeners();
    }
  }

  Future<bool> acceptInvitation(String journeyId) async {
    _isAccepting = true;
    _acceptError = null;
    notifyListeners();

    final result = await acceptInvitationUseCase(journeyId);

    if (result.isSuccess) {
      _acceptedJourneyIds.add(journeyId);
      _invitations.removeWhere((inv) => inv.journeyId == journeyId);
      _isAccepting = false;
      notifyListeners();
      return true;
    } else {
      _acceptError = result.failure?.message ?? 'Failed to accept invitation';
      _isAccepting = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> declineInvitation(String journeyId) async {
    _isDeclining = true;
    _declineError = null;
    notifyListeners();

    final result = await declineInvitationUseCase(journeyId);
    if (result.isSuccess) {
      _invitations.removeWhere((inv) => inv.journeyId == journeyId);
      _isDeclining = false;
      notifyListeners();
      return true;
    }

    _declineError = result.failure?.message ?? 'Failed to decline invitation';
    _isDeclining = false;
    notifyListeners();
    return false;
  }
}

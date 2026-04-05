import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../core/common/result.dart';
import '../../domain/entities/invitation.dart';
import '../../domain/usecases/send_invitation_usecase.dart';
import '../../domain/usecases/get_participants_usecase.dart';
import '../../domain/usecases/search_users_usecase.dart';
import '../../domain/usecases/respond_invitation_usecase.dart';
import '../../domain/repositories/invitation_repository.dart';

class InvitationProvider extends ChangeNotifier {
  final SendInvitationUseCase _sendInvitationUseCase;
  final GetParticipantsUseCase _getParticipantsUseCase;
  final SearchUsersUseCase _searchUsersUseCase;
  final RespondInvitationUseCase _respondInvitationUseCase;
  final InvitationRepository _invitationRepository;

  InvitationProvider({
    required SendInvitationUseCase sendInvitationUseCase,
    required GetParticipantsUseCase getParticipantsUseCase,
    required SearchUsersUseCase searchUsersUseCase,
    required RespondInvitationUseCase respondInvitationUseCase,
    required InvitationRepository invitationRepository,
  })  : _sendInvitationUseCase = sendInvitationUseCase,
        _getParticipantsUseCase = getParticipantsUseCase,
        _searchUsersUseCase = searchUsersUseCase,
        _respondInvitationUseCase = respondInvitationUseCase,
        _invitationRepository = invitationRepository {
    _initializeStreams();
  }

  // State
  List<JourneyParticipant> _participants = [];
  List<Invitation> _invitations = [];
  List<User> _searchResults = [];
  bool _isLoading = false;
  bool _isSearching = false;
  bool _isSendingInvitation = false;
  String? _error;
  String? _currentJourneyId;

  // Getters
  List<JourneyParticipant> get participants => _participants;
  List<Invitation> get invitations => _invitations;
  List<User> get searchResults => _searchResults;
  bool get isLoading => _isLoading;
  bool get isSearching => _isSearching;
  bool get isSendingInvitation => _isSendingInvitation;
  String? get error => _error;
  String? get currentJourneyId => _currentJourneyId;

  // Computed properties
  List<JourneyParticipant> get activeParticipants {
    return _participants.where((p) => p.status == ParticipantStatus.active).toList();
  }

  List<Invitation> get pendingInvitations {
    return _invitations.where((i) => i.isPending).toList();
  }

  int get totalParticipantsCount {
    return activeParticipants.length;
  }

  bool get canStartJourney {
    // Journey can start if there's at least one participant (the leader)
    return activeParticipants.isNotEmpty;
  }

  StreamSubscription<List<JourneyParticipant>>? _participantsSubscription;
  StreamSubscription<List<Invitation>>? _invitationsSubscription;

  void _initializeStreams() {
    _participantsSubscription = _invitationRepository.participantsStream.listen(
      (participants) {
        _participants = participants;
        notifyListeners();
      },
    );

    _invitationsSubscription = _invitationRepository.invitationsStream.listen(
      (invitations) {
        _invitations = invitations;
        notifyListeners();
      },
    );
  }

  Future<void> initializeForJourney(String journeyId) async {
    if (_currentJourneyId == journeyId) return;

    _currentJourneyId = journeyId;
    _error = null;
    
    // Stop previous real-time updates
    _invitationRepository.stopRealTimeUpdates();
    
    // Start real-time updates for new journey
    _invitationRepository.startRealTimeUpdates(journeyId);
    
    // Load initial data
    await Future.wait([
      loadParticipants(journeyId),
      loadInvitations(journeyId),
    ]);
  }

  Future<void> loadParticipants(String journeyId) async {
    _setLoading(true);
    
    final result = await _getParticipantsUseCase(journeyId);
    
    if (result.isSuccess && result.data != null) {
      _participants = result.data!;
      _error = null;
    } else if (result.failure != null) {
      _error = result.failure!.message;
    }
    
    _setLoading(false);
  }

  Future<void> loadInvitations(String journeyId) async {
    final result = await _invitationRepository.getInvitations(journeyId);
    
    if (result.isSuccess && result.data != null) {
      _invitations = result.data!;
      _error = null;
    } else if (result.failure != null) {
      _error = result.failure!.message;
    }
  }

  Future<void> searchUsers(String query) async {
    if (query.trim().isEmpty) {
      _searchResults = [];
      notifyListeners();
      return;
    }

    _setSearching(true);
    
    final result = await _searchUsersUseCase(query);
    
    if (result.isSuccess && result.data != null) {
      _searchResults = result.data!;
      _error = null;
    } else {
      if (result.failure != null) {
        _error = result.failure!.message;
      }
      _searchResults = [];
    }
    
    _setSearching(false);
  }

  Future<bool> sendInvitation({
    required String journeyId,
    required String inviteeId,
    String? message,
  }) async {
    _setSendingInvitation(true);
    
    final result = await _sendInvitationUseCase(
      SendInvitationParams(
        journeyId: journeyId,
        inviteeId: inviteeId,
        message: message,
      ),
    );
    
    bool success = false;
    if (result.isSuccess) {
      success = true;
      _error = null;
      // Clear search results after successful invitation
      _searchResults = [];
    } else if (result.failure != null) {
      _error = result.failure!.message;
    }
    
    _setSendingInvitation(false);
    return success;
  }

  Future<bool> respondToInvitation({
    required String invitationId,
    required bool accept,
  }) async {
    _setLoading(true);
    
    final result = await _respondInvitationUseCase(
      RespondInvitationParams(
        invitationId: invitationId,
        accept: accept,
      ),
    );
    
    bool success = false;
    if (result.isSuccess) {
      success = true;
      _error = null;
    } else if (result.failure != null) {
      _error = result.failure!.message;
    }
    
    _setLoading(false);
    return success;
  }

  Future<bool> removeParticipant({
    required String journeyId,
    required String participantId,
  }) async {
    _setLoading(true);
    
    final result = await _invitationRepository.removeParticipant(
      journeyId: journeyId,
      participantId: participantId,
    );
    
    bool success = false;
    if (result.isSuccess) {
      success = true;
      _error = null;
    } else if (result.failure != null) {
      _error = result.failure!.message;
    }
    
    _setLoading(false);
    return success;
  }

  Future<bool> cancelInvitation(String invitationId) async {
    _setLoading(true);
    
    final result = await _invitationRepository.cancelInvitation(invitationId);
    
    bool success = false;
    if (result.isSuccess) {
      success = true;
      _error = null;
    } else if (result.failure != null) {
      _error = result.failure!.message;
    }
    
    _setLoading(false);
    return success;
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void clearSearchResults() {
    _searchResults = [];
    notifyListeners();
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setSearching(bool searching) {
    _isSearching = searching;
    notifyListeners();
  }

  void _setSendingInvitation(bool sending) {
    _isSendingInvitation = sending;
    notifyListeners();
  }

  @override
  void dispose() {
    _participantsSubscription?.cancel();
    _invitationsSubscription?.cancel();
    _invitationRepository.stopRealTimeUpdates();
    super.dispose();
  }
}
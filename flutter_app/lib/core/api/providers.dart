import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../models/models.dart';
import 'dio_client.dart';
import 'api_services.dart';

// ── Services ──────────────────────────────────────────────────

final dioProvider = Provider<Dio>((ref) => buildDioClient());
final authServiceProvider = Provider((ref) => AuthService(ref.watch(dioProvider)));
final labelServiceProvider = Provider((ref) => LabelService(ref.watch(dioProvider)));
final recordingServiceProvider = Provider((ref) => RecordingService(ref.watch(dioProvider)));
final segmentServiceProvider = Provider((ref) => SegmentService(ref.watch(dioProvider)));
final suggestionServiceProvider = Provider((ref) => SuggestionService(ref.watch(dioProvider)));
final consensusServiceProvider = Provider((ref) => ConsensusService(ref.watch(dioProvider)));
final trainingPoolServiceProvider = Provider((ref) => TrainingPoolService(ref.watch(dioProvider)));
final researcherServiceProvider = Provider((ref) => ResearcherService(ref.watch(dioProvider)));
final exportServiceProvider = Provider((ref) => ExportService(ref.watch(dioProvider)));

// ── Auth ──────────────────────────────────────────────────────

class AuthState {
  final User? user;
  final bool isLoading;
  final String? error;

  const AuthState({this.user, this.isLoading = false, this.error});

  bool get isAuthenticated => user != null;
  bool get isResearcher => user?.isResearcher ?? false;

  AuthState copyWith({User? user, bool? isLoading, String? error}) =>
      AuthState(user: user ?? this.user, isLoading: isLoading ?? this.isLoading, error: error);
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService _auth;
  AuthNotifier(this._auth) : super(const AuthState()) {
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final token = await readToken();
    if (token == null) return;
    try {
      final user = await _auth.me();
      state = AuthState(user: user);
    } catch (_) {
      await clearToken();
    }
  }

  Future<void> login(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await _auth.login(email: email, password: password);
      await saveToken(result.accessToken);
      state = AuthState(user: result.user);
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false, error: e.response?.data?['detail'] ?? 'Login failed');
    }
  }

  Future<void> register(String email, String password, String? displayName, {String role = 'contributor'}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await _auth.register(
          email: email, password: password, displayName: displayName, role: role);
      await saveToken(result.accessToken);
      state = AuthState(user: result.user);
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false, error: e.response?.data?['detail'] ?? 'Registration failed');
    }
  }

  Future<void> logout() async {
    await clearToken();
    state = const AuthState();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
    (ref) => AuthNotifier(ref.watch(authServiceProvider)));

// ── Labels (cached globally) ──────────────────────────────────

final labelsProvider = FutureProvider<List<AppLabel>>((ref) {
  return ref.watch(labelServiceProvider).fetchLabels();
});

// ── My Clips ──────────────────────────────────────────────────

final mySegmentsProvider = FutureProvider.family<List<Segment>, String>((ref, reviewStatus) {
  return ref.watch(segmentServiceProvider).listMySegments(reviewStatus: reviewStatus);
});

// All own segments regardless of status (for "All" tab)
final allMySegmentsProvider = FutureProvider<List<Segment>>((ref) {
  return ref.watch(segmentServiceProvider).listMySegments(sort: 'confidence_asc');
});

// ── Suggestion queue ──────────────────────────────────────────

final suggestionQueueProvider = FutureProvider<List<Segment>>((ref) {
  return ref.watch(suggestionServiceProvider).getQueue();
});

// ── Consensus ─────────────────────────────────────────────────

final consensusOpenProvider = FutureProvider<List<Segment>>((ref) {
  return ref.watch(consensusServiceProvider).getOpenVotes();
});

// ── Training pool ─────────────────────────────────────────────

final trainingPoolProvider = FutureProvider.family<List<Segment>, String>((ref, sort) {
  return ref.watch(trainingPoolServiceProvider).list(sort: sort);
});

// ── Researcher queue ──────────────────────────────────────────

final researcherQueueProvider = FutureProvider<List<Segment>>((ref) {
  return ref.watch(researcherServiceProvider).getReviewQueue();
});

// ── Export ────────────────────────────────────────────────────

final exportStatsProvider = FutureProvider<ExportStats>((ref) {
  return ref.watch(researcherServiceProvider).getStats();
});

final myExportsProvider = FutureProvider<List<ExportJob>>((ref) {
  return ref.watch(exportServiceProvider).listMyExports();
});

// ── Recordings ────────────────────────────────────────────────

final myRecordingsProvider = FutureProvider<List<Recording>>((ref) {
  return ref.watch(recordingServiceProvider).listMyRecordings();
});

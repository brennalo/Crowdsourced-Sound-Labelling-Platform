import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../models/models.dart';
import 'dio_client.dart';
import 'api_services.dart';

// ── Core ──────────────────────────────────────────────────────

final dioProvider = Provider<Dio>((ref) => buildDioClient());

final authServiceProvider = Provider((ref) => AuthService(ref.watch(dioProvider)));
final recordingServiceProvider = Provider((ref) => RecordingService(ref.watch(dioProvider)));
final segmentServiceProvider = Provider((ref) => SegmentService(ref.watch(dioProvider)));
final annotationServiceProvider = Provider((ref) => AnnotationService(ref.watch(dioProvider)));
final suggestionServiceProvider = Provider((ref) => SuggestionService(ref.watch(dioProvider)));

// ── Auth state ────────────────────────────────────────────────

class AuthState {
  final User? user;
  final bool isLoading;
  final String? error;

  const AuthState({this.user, this.isLoading = false, this.error});

  bool get isAuthenticated => user != null;
  AuthState copyWith({User? user, bool? isLoading, String? error}) => AuthState(
        user: user ?? this.user,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
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
      final msg = e.response?.data?['detail'] ?? 'Login failed';
      state = state.copyWith(isLoading: false, error: msg);
    }
  }

  Future<void> register(String email, String password, String? displayName) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await _auth.register(
        email: email, password: password, displayName: displayName,
      );
      await saveToken(result.accessToken);
      state = AuthState(user: result.user);
    } on DioException catch (e) {
      final msg = e.response?.data?['detail'] ?? 'Registration failed';
      state = state.copyWith(isLoading: false, error: msg);
    }
  }

  Future<void> logout() async {
    await clearToken();
    state = const AuthState();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(ref.watch(authServiceProvider)),
);

// ── Recordings ────────────────────────────────────────────────

final myRecordingsProvider = FutureProvider<List<Recording>>((ref) {
  return ref.watch(recordingServiceProvider).listMyRecordings();
});

// ── Segments for a recording ──────────────────────────────────

final recordingSegmentsProvider = FutureProvider.family<List<Segment>, String>((ref, recordingId) {
  return ref.watch(segmentServiceProvider).listSegments(recordingId: recordingId);
});

// ── Pending segments (for manual annotation queue) ────────────

final pendingSegmentsProvider = FutureProvider<List<Segment>>((ref) {
  return ref.watch(segmentServiceProvider).listSegments(reviewStatus: 'pending');
});

// ── Suggestion queue ──────────────────────────────────────────

final suggestionQueueProvider = FutureProvider<List<Segment>>((ref) {
  return ref.watch(suggestionServiceProvider).getSuggestionQueue();
});

// ── Segment audio URL ─────────────────────────────────────────

final segmentAudioUrlProvider = FutureProvider.family<String, String>((ref, segmentId) {
  return ref.watch(segmentServiceProvider).getAudioUrl(segmentId);
});

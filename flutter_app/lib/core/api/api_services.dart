import 'dart:io';
import 'package:dio/dio.dart';
import '../models/models.dart';

// ── Auth ──────────────────────────────────────────────────────

class AuthService {
  final Dio _dio;
  AuthService(this._dio);

  Future<AuthToken> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final res = await _dio.post('/auth/register', data: {
      'email': email,
      'password': password,
      if (displayName != null) 'display_name': displayName,
    });
    return AuthToken.fromJson(res.data);
  }

  Future<AuthToken> login({
    required String email,
    required String password,
  }) async {
    final res = await _dio.post('/auth/login', data: {
      'email': email,
      'password': password,
    });
    return AuthToken.fromJson(res.data);
  }

  Future<User> me() async {
    final res = await _dio.get('/auth/me');
    return User.fromJson(res.data);
  }
}

// ── Recordings ───────────────────────────────────────────────

class RecordingService {
  final Dio _dio;
  RecordingService(this._dio);

  Future<Recording> uploadRecording({
    required File audioFile,
    DateTime? recordedAt,
    double? lat,
    double? lng,
  }) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        audioFile.path,
        filename: 'recording.wav',
        contentType: DioMediaType('audio', 'wav'),
      ),
      if (recordedAt != null) 'recorded_at': recordedAt.toIso8601String(),
      if (lat != null) 'location_lat': lat.toString(),
      if (lng != null) 'location_lng': lng.toString(),
    });

    final res = await _dio.post(
      '/recordings/',
      data: formData,
      options: Options(
        contentType: 'multipart/form-data',
        sendTimeout: const Duration(minutes: 5),
      ),
    );
    return Recording.fromJson(res.data);
  }

  Future<List<Recording>> listMyRecordings() async {
    final res = await _dio.get('/recordings/');
    return (res.data as List).map((j) => Recording.fromJson(j)).toList();
  }

  Future<Recording> getRecording(String id) async {
    final res = await _dio.get('/recordings/$id');
    return Recording.fromJson(res.data);
  }
}

// ── Segments ─────────────────────────────────────────────────

class SegmentService {
  final Dio _dio;
  SegmentService(this._dio);

  Future<List<Segment>> listSegments({
    String? recordingId,
    String? reviewStatus,
  }) async {
    final res = await _dio.get('/segments/', queryParameters: {
      if (recordingId != null) 'recording_id': recordingId,
      if (reviewStatus != null) 'review_status': reviewStatus,
    });
    return (res.data as List).map((j) => Segment.fromJson(j)).toList();
  }

  Future<String> getAudioUrl(String segmentId) async {
    final res = await _dio.get('/segments/$segmentId/audio-url');
    return res.data['url'] as String;
  }
}

// ── Annotations ──────────────────────────────────────────────

class AnnotationService {
  final Dio _dio;
  AnnotationService(this._dio);

  Future<Annotation> annotateSegment({
    required String segmentId,
    required String label,
  }) async {
    final res = await _dio.post('/annotations/$segmentId', data: {'label': label});
    return Annotation.fromJson(res.data);
  }

  Future<List<Annotation>> getSegmentAnnotations(String segmentId) async {
    final res = await _dio.get('/annotations/$segmentId');
    return (res.data as List).map((j) => Annotation.fromJson(j)).toList();
  }
}

// ── Suggestions ──────────────────────────────────────────────

class SuggestionService {
  final Dio _dio;
  SuggestionService(this._dio);

  Future<List<Segment>> getSuggestionQueue({int limit = 20}) async {
    final res = await _dio.get('/suggestions/queue', queryParameters: {'limit': limit});
    return (res.data as List).map((j) => Segment.fromJson(j)).toList();
  }

  Future<void> reviewSuggestion({
    required String segmentId,
    required String decision, // accepted | rejected
  }) async {
    await _dio.post('/suggestions/$segmentId/review', data: {'decision': decision});
  }
}

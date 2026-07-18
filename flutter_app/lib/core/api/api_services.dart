import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../models/models.dart';

class AuthService {
  final Dio _dio;
  AuthService(this._dio);

  Future<AuthToken> register({
    required String email,
    required String password,
    String? displayName,
    String role = 'contributor',
  }) async {
    final res = await _dio.post('/auth/register', data: {
      'email': email,
      'password': password,
      if (displayName != null) 'display_name': displayName,
      'role': role,
    });
    return AuthToken.fromJson(res.data);
  }

  Future<AuthToken> login(
      {required String email, required String password}) async {
    final res = await _dio
        .post('/auth/login', data: {'email': email, 'password': password});
    return AuthToken.fromJson(res.data);
  }

  Future<User> me() async {
    final res = await _dio.get('/auth/me');
    return User.fromJson(res.data);
  }
}

class LabelService {
  final Dio _dio;
  LabelService(this._dio);

  Future<List<AppLabel>> fetchLabels() async {
    final res = await _dio.get('/labels/');
    return (res.data as List).map((j) => AppLabel.fromJson(j)).toList();
  }

  /// Researcher-only — includes inactive labels.
  Future<List<AppLabel>> fetchAllLabels() async {
    final res = await _dio.get('/labels/all');
    return (res.data as List).map((j) => AppLabel.fromJson(j)).toList();
  }

  /// Researcher-only — add a new label to the taxonomy.
  Future<AppLabel> createLabel(
      {required String name, required String displayName}) async {
    final res = await _dio.post('/labels/', data: {
      'name': name,
      'display_name': displayName,
    });
    return AppLabel.fromJson(res.data);
  }

  /// Researcher-only — activate or deactivate a label (soft delete).
  Future<AppLabel> setLabelActive(String labelId, bool isActive) async {
    final res =
        await _dio.patch('/labels/$labelId', data: {'is_active': isActive});
    return AppLabel.fromJson(res.data);
  }
}

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
    final res = await _dio.post('/recordings/',
        data: formData, options: Options(contentType: 'multipart/form-data'));
    return Recording.fromJson(res.data);
  }

  /// Web path: upload raw bytes captured from the recorder's blob output.
  Future<Recording> uploadRecordingBytes({
    required Uint8List bytes,
    DateTime? recordedAt,
    double? lat,
    double? lng,
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: 'recording.wav',
        contentType: DioMediaType('audio', 'wav'),
      ),
      if (recordedAt != null) 'recorded_at': recordedAt.toIso8601String(),
      if (lat != null) 'location_lat': lat.toString(),
      if (lng != null) 'location_lng': lng.toString(),
    });
    final res = await _dio.post('/recordings/',
        data: formData, options: Options(contentType: 'multipart/form-data'));
    return Recording.fromJson(res.data);
  }

  // Future<Uint8List> fetchBlobBytes(String blobUrl) async {
  //   final res = await _dio.get<List<int>>(
  //     blobUrl,
  //     options: Options(responseType: ResponseType.bytes),
  //   );
  //   return Uint8List.fromList(res.data!);
  // }

  Future<List<Recording>> listMyRecordings() async {
    final res = await _dio.get('/recordings/');
    return (res.data as List).map((j) => Recording.fromJson(j)).toList();
  }
}

class SegmentService {
  final Dio _dio;
  SegmentService(this._dio);

  Future<List<Segment>> listMySegments({
    String? reviewStatus,
    String? recordingId,
    String sort = 'confidence_asc',
  }) async {
    final res = await _dio.get('/segments/my', queryParameters: {
      if (reviewStatus != null) 'review_status': reviewStatus,
      if (recordingId != null) 'recording_id': recordingId,
      'sort': sort,
    });
    return (res.data as List).map((j) => Segment.fromJson(j)).toList();
  }

  Future<Segment> updateOwnLabel(String segmentId, String label) async {
    final res = await _dio
        .patch('/segments/my/$segmentId/label', data: {'label': label});
    return Segment.fromJson(res.data);
  }

  Future<String> getAudioUrl(String segmentId) async {
    final res = await _dio.get('/segments/$segmentId/audio-url');
    return res.data['url'] as String;
  }
}

class SuggestionService {
  final Dio _dio;
  SuggestionService(this._dio);

  Future<List<Segment>> getQueue() async {
    final res = await _dio.get('/suggestions/queue');
    return (res.data as List).map((j) => Segment.fromJson(j)).toList();
  }

  Future<Segment> reviewSuggestion({
    required String segmentId,
    required String decision,
    String? correctedLabel,
  }) async {
    final res = await _dio.post('/suggestions/$segmentId/review', data: {
      'decision': decision,
      if (correctedLabel != null) 'corrected_label': correctedLabel,
    });
    return Segment.fromJson(res.data);
  }
}

class ConsensusService {
  final Dio _dio;
  ConsensusService(this._dio);

  Future<List<Segment>> getOpenVotes() async {
    final res = await _dio.get('/consensus/open');
    return (res.data as List).map((j) => Segment.fromJson(j)).toList();
  }

  Future<void> reportSegment(String segmentId) async {
    await _dio.post('/consensus/report/$segmentId');
  }

  Future<Map<String, dynamic>> castVote(
      String segmentId, String verdict) async {
    final res = await _dio
        .post('/consensus/vote/$segmentId', data: {'verdict': verdict});
    return res.data as Map<String, dynamic>;
  }
}

class TrainingPoolService {
  final Dio _dio;
  TrainingPoolService(this._dio);

  Future<List<Segment>> list({
    String sort = 'time_desc',
    String? label,
    int limit = 50,
    int offset = 0,
  }) async {
    final res = await _dio.get('/training-pool/', queryParameters: {
      'sort': sort,
      if (label != null) 'label': label,
      'limit': limit,
      'offset': offset,
    });
    return (res.data as List).map((j) => Segment.fromJson(j)).toList();
  }
}

class ResearcherService {
  final Dio _dio;
  ResearcherService(this._dio);

  Future<List<Segment>> getReviewQueue() async {
    final res = await _dio.get('/researcher/queue');
    return (res.data as List).map((j) => Segment.fromJson(j)).toList();
  }

  Future<void> submitReview({
    required String segmentId,
    required String action,
    String? correctedLabel,
  }) async {
    await _dio.post('/researcher/review/$segmentId', data: {
      'action': action,
      if (correctedLabel != null) 'corrected_label': correctedLabel,
    });
  }

  Future<void> triggerRetrain() async {
    await _dio.post('/researcher/retrain');
  }

  Future<ExportStats> getStats() async {
    final res = await _dio.get('/researcher/stats');
    return ExportStats.fromJson(res.data);
  }

  Future<List<RetrainingJob>> listRetrainingJobs() async {
    final res = await _dio.get('/model/retraining-jobs');
    return (res.data as List).map((j) => RetrainingJob.fromJson(j)).toList();
  }
}

class ExportService {
  final Dio _dio;
  ExportService(this._dio);

  Future<ExportJob> requestExport() async {
    final res = await _dio.post('/exports/');
    return ExportJob.fromJson(res.data);
  }

  Future<List<ExportJob>> listMyExports() async {
    final res = await _dio.get('/exports/my');
    return (res.data as List).map((j) => ExportJob.fromJson(j)).toList();
  }

  Future<String> getDownloadUrl(String jobId) async {
    final res = await _dio.get('/exports/$jobId/download');
    return res.data['download_url'] as String;
  }
}

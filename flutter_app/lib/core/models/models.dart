// lib/core/models/models.dart

class User {
  final String id;
  final String email;
  final String? displayName;
  final String role;
  final DateTime createdAt;

  const User({
    required this.id,
    required this.email,
    this.displayName,
    required this.role,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> j) => User(
        id: j['id'],
        email: j['email'],
        displayName: j['display_name'],
        role: j['role'],
        createdAt: DateTime.parse(j['created_at']),
      );

  String get name => displayName ?? email.split('@').first;
}

class AuthToken {
  final String accessToken;
  final User user;

  const AuthToken({required this.accessToken, required this.user});

  factory AuthToken.fromJson(Map<String, dynamic> j) => AuthToken(
        accessToken: j['access_token'],
        user: User.fromJson(j['user']),
      );
}

class Recording {
  final String id;
  final String userId;
  final String gcsRawPath;
  final double? durationSec;
  final DateTime? recordedAt;
  final double? locationLat;
  final double? locationLng;
  final String status;
  final DateTime createdAt;

  const Recording({
    required this.id,
    required this.userId,
    required this.gcsRawPath,
    this.durationSec,
    this.recordedAt,
    this.locationLat,
    this.locationLng,
    required this.status,
    required this.createdAt,
  });

  factory Recording.fromJson(Map<String, dynamic> j) => Recording(
        id: j['id'],
        userId: j['user_id'],
        gcsRawPath: j['gcs_raw_path'],
        durationSec: (j['duration_sec'] as num?)?.toDouble(),
        recordedAt: j['recorded_at'] != null ? DateTime.parse(j['recorded_at']) : null,
        locationLat: (j['location_lat'] as num?)?.toDouble(),
        locationLng: (j['location_lng'] as num?)?.toDouble(),
        status: j['status'],
        createdAt: DateTime.parse(j['created_at']),
      );

  bool get isProcessing => status == 'processing';
  bool get isDone => status == 'done';
  bool get isFailed => status == 'failed';
}

class Segment {
  final String id;
  final String recordingId;
  final String userId;
  final String gcsPath;
  final double startSec;
  final double endSec;
  final String reviewStatus;
  final DateTime createdAt;

  // From suggestion queue
  final String? predictedLabel;
  final double? confidence;
  final String? annotationId;

  const Segment({
    required this.id,
    required this.recordingId,
    required this.userId,
    required this.gcsPath,
    required this.startSec,
    required this.endSec,
    required this.reviewStatus,
    required this.createdAt,
    this.predictedLabel,
    this.confidence,
    this.annotationId,
  });

  factory Segment.fromJson(Map<String, dynamic> j) => Segment(
        id: j['id'],
        recordingId: j['recording_id'],
        userId: j['user_id'],
        gcsPath: j['gcs_path'],
        startSec: (j['start_sec'] as num).toDouble(),
        endSec: (j['end_sec'] as num).toDouble(),
        reviewStatus: j['review_status'],
        createdAt: DateTime.parse(j['created_at']),
        predictedLabel: j['predicted_label'],
        confidence: (j['confidence'] as num?)?.toDouble(),
        annotationId: j['annotation_id'],
      );

  double get durationSec => endSec - startSec;
  bool get isPending => reviewStatus == 'pending';
  bool get isAnnotated => reviewStatus == 'annotated';
}

class Annotation {
  final String id;
  final String segmentId;
  final String label;
  final String source;
  final double? confidence;
  final DateTime createdAt;

  const Annotation({
    required this.id,
    required this.segmentId,
    required this.label,
    required this.source,
    this.confidence,
    required this.createdAt,
  });

  factory Annotation.fromJson(Map<String, dynamic> j) => Annotation(
        id: j['id'],
        segmentId: j['segment_id'],
        label: j['label'],
        source: j['source'],
        confidence: (j['confidence'] as num?)?.toDouble(),
        createdAt: DateTime.parse(j['created_at']),
      );
}

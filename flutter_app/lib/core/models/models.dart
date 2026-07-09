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
  bool get isResearcher => role == 'researcher' || role == 'admin';
  bool get isContributor => role == 'contributor' || role == 'admin';
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

class AppLabel {
  final String id;
  final String name;
  final String displayName;

  const AppLabel({required this.id, required this.name, required this.displayName});

  factory AppLabel.fromJson(Map<String, dynamic> j) => AppLabel(
        id: j['id'],
        name: j['name'],
        displayName: j['display_name'],
      );
}

class Recording {
  final String id;
  final String userId;
  final double? durationSec;
  final DateTime? recordedAt;
  final String status;
  final DateTime createdAt;

  const Recording({
    required this.id,
    required this.userId,
    this.durationSec,
    this.recordedAt,
    required this.status,
    required this.createdAt,
  });

  factory Recording.fromJson(Map<String, dynamic> j) => Recording(
        id: j['id'],
        userId: j['user_id'],
        durationSec: (j['duration_sec'] as num?)?.toDouble(),
        recordedAt: j['recorded_at'] != null ? DateTime.parse(j['recorded_at']) : null,
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
  final String? effectiveLabel;
  final String? modelLabel;
  final double? modelConfidence;
  final String? poolEntryReason;
  final DateTime createdAt;

  // Training pool extras
  final String? uploaderDisplayName;
  final int agreeCount;
  final int disagreeCount;
  final bool consensusOpen;

  const Segment({
    required this.id,
    required this.recordingId,
    required this.userId,
    required this.gcsPath,
    required this.startSec,
    required this.endSec,
    required this.reviewStatus,
    this.effectiveLabel,
    this.modelLabel,
    this.modelConfidence,
    this.poolEntryReason,
    required this.createdAt,
    this.uploaderDisplayName,
    this.agreeCount = 0,
    this.disagreeCount = 0,
    this.consensusOpen = false,
  });

  factory Segment.fromJson(Map<String, dynamic> j) => Segment(
        id: j['id'],
        recordingId: j['recording_id'],
        userId: j['user_id'],
        gcsPath: j['gcs_path'],
        startSec: (j['start_sec'] as num).toDouble(),
        endSec: (j['end_sec'] as num).toDouble(),
        reviewStatus: j['review_status'],
        effectiveLabel: j['effective_label'],
        modelLabel: j['model_label'],
        modelConfidence: (j['model_confidence'] as num?)?.toDouble(),
        poolEntryReason: j['pool_entry_reason'],
        createdAt: DateTime.parse(j['created_at']),
        uploaderDisplayName: j['uploader_display_name'],
        agreeCount: j['agree_count'] ?? 0,
        disagreeCount: j['disagree_count'] ?? 0,
        consensusOpen: j['consensus_open'] ?? false,
      );

  double get durationSec => endSec - startSec;

  bool get isAnnotationPending => reviewStatus == 'annotation_pending';
  bool get isSuggestionPending => reviewStatus == 'suggestion_pending';
  bool get isInPool => reviewStatus == 'training_pool' || reviewStatus == 'consensus_open';
  bool get isExcludedOther => reviewStatus == 'excluded_other';
  bool get needsAction => isAnnotationPending || isSuggestionPending;
}

class ExportJob {
  final String id;
  final String status;
  final String? gcsExportPath;
  final DateTime requestedAt;
  final DateTime? completedAt;

  const ExportJob({
    required this.id,
    required this.status,
    this.gcsExportPath,
    required this.requestedAt,
    this.completedAt,
  });

  factory ExportJob.fromJson(Map<String, dynamic> j) => ExportJob(
        id: j['id'],
        status: j['status'],
        gcsExportPath: j['gcs_export_path'],
        requestedAt: DateTime.parse(j['requested_at']),
        completedAt: j['completed_at'] != null ? DateTime.parse(j['completed_at']) : null,
      );

  bool get isDone => status == 'done';
  bool get isFailed => status == 'failed';
}

class ExportStats {
  final int totalInPool;
  final Map<String, int> labelDistribution;
  final int consensusFlips;
  final int researcherCorrections;
  final int addedLast7Days;

  const ExportStats({
    required this.totalInPool,
    required this.labelDistribution,
    required this.consensusFlips,
    required this.researcherCorrections,
    required this.addedLast7Days,
  });

  factory ExportStats.fromJson(Map<String, dynamic> j) => ExportStats(
        totalInPool: j['total_in_pool'],
        labelDistribution: Map<String, int>.from(j['label_distribution']),
        consensusFlips: j['consensus_flips'],
        researcherCorrections: j['researcher_corrections'],
        addedLast7Days: j['added_last_7_days'],
      );
}

//Programmer Name - Brenna Lo
//Program Name : models.dart
// Description : Data models for the Flutter app
// First Written on : 2024-06-10
// Edited on : 2024-07-18

class User {
  final String id;
  final String email;
  final String? displayName;
  final String role;
  final bool isActive;
  final DateTime createdAt;

  const User({
    required this.id,
    required this.email,
    this.displayName,
    required this.role,
    this.isActive = true,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> j) => User(
        id: j['id'],
        email: j['email'],
        displayName: j['display_name'],
        role: j['role'],
        isActive: j['is_active'] ?? true,
        createdAt: DateTime.parse(j['created_at']),
      );

  String get name => displayName ?? email.split('@').first;
  bool get isResearcher => role == 'researcher' || role == 'admin';
  bool get isContributor => role == 'contributor' || role == 'admin';
  bool get isAdmin => role == 'admin';
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
  final bool isActive;
  final DateTime? createdAt;

  const AppLabel({
    required this.id,
    required this.name,
    required this.displayName,
    this.isActive = true,
    this.createdAt,
  });

  factory AppLabel.fromJson(Map<String, dynamic> j) => AppLabel(
        id: j['id'],
        name: j['name'],
        displayName: j['display_name'],
        isActive: j['is_active'] ?? true,
        createdAt:
            j['created_at'] != null ? DateTime.parse(j['created_at']) : null,
      );
}

class Recording {
  final String id;
  final String userId;
  final double? durationSec;
  final DateTime? recordedAt;
  final String status;
  final int? totalSegments;
  final DateTime createdAt;

  const Recording({
    required this.id,
    required this.userId,
    this.durationSec,
    this.recordedAt,
    required this.status,
    this.totalSegments,
    required this.createdAt,
  });

  factory Recording.fromJson(Map<String, dynamic> j) => Recording(
        id: j['id'],
        userId: j['user_id'],
        durationSec: (j['duration_sec'] as num?)?.toDouble(),
        recordedAt:
            j['recorded_at'] != null ? DateTime.parse(j['recorded_at']) : null,
        status: j['status'],
        totalSegments: j['total_segments'] as int?,
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

  // Consensus extras
  final bool userVoted;

  // Identifier / display context
  final int? sequenceNum;
  final DateTime? recordingRecordedAt;
  final int? recordingTotalSegments;

  // Consensus: label proposed by whoever reported this segment wrong
  final String? proposedLabel;

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
    this.userVoted = false,
    this.sequenceNum,
    this.recordingRecordedAt,
    this.recordingTotalSegments,
    this.proposedLabel,
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
        userVoted: j['user_voted'] ?? false,
        sequenceNum: j['sequence_num'] as int?,
        recordingRecordedAt: j['recording_recorded_at'] != null
            ? DateTime.parse(j['recording_recorded_at'])
            : null,
        recordingTotalSegments: j['recording_total_segments'] as int?,
        proposedLabel: j['proposed_label'] as String?,
      );

  double get durationSec => endSec - startSec;

  bool get isAnnotationPending => reviewStatus == 'annotation_pending';
  bool get isSuggestionPending => reviewStatus == 'suggestion_pending';
  bool get isInPool =>
      reviewStatus == 'training_pool' || reviewStatus == 'consensus_open';
  bool get isExcludedOther => reviewStatus == 'excluded_other';
  bool get needsAction => isAnnotationPending || isSuggestionPending;

  /// Human-friendly identifier for flat-list views, e.g.
  /// "Jul 15, 9:42 AM · Segment 3/40" or, once a contributor is mixed in
  /// (consensus / training pool / researcher review), "... · by Maria".
  /// Falls back to the raw start–end seconds if recording context wasn't
  /// included in this particular API response.
  String get displayLabel {
    final parts = <String>[];
    if (recordingRecordedAt != null) {
      parts.add(_formatShortDateTime(recordingRecordedAt!));
    }
    if (sequenceNum != null) {
      parts.add(recordingTotalSegments != null
          ? 'Segment $sequenceNum/$recordingTotalSegments'
          : 'Segment $sequenceNum');
    }
    if (uploaderDisplayName != null && uploaderDisplayName!.isNotEmpty) {
      parts.add('by $uploaderDisplayName');
    }
    if (parts.isEmpty) {
      return '${startSec.toStringAsFixed(1)}s – ${endSec.toStringAsFixed(1)}s';
    }
    return parts.join(' · ');
  }
}

const _shortMonths = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Small local formatter so we don't need to pull in `intl` just for this —
/// e.g. "Jul 15, 9:42 AM". Uses the device's local time zone.
String _formatShortDateTime(DateTime dt) {
  final local = dt.toLocal();
  final month = _shortMonths[local.month - 1];
  final hour24 = local.hour;
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = hour24 < 12 ? 'AM' : 'PM';
  return '$month ${local.day}, $hour12:$minute $period';
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
        completedAt: j['completed_at'] != null
            ? DateTime.parse(j['completed_at'])
            : null,
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

class RetrainingJob {
  final String id;
  final DateTime triggeredAt;
  final String triggeredBy;
  final String status;
  final int? rejectionCount;
  final DateTime? completedAt;
  final String? errorLog;

  RetrainingJob({
    required this.id,
    required this.triggeredAt,
    required this.triggeredBy,
    required this.status,
    this.rejectionCount,
    this.completedAt,
    this.errorLog,
  });

  factory RetrainingJob.fromJson(Map<String, dynamic> json) => RetrainingJob(
        id: json['id'] as String,
        triggeredAt: DateTime.parse(json['triggered_at'] as String),
        triggeredBy: json['triggered_by'] as String,
        status: json['status'] as String,
        rejectionCount: json['rejection_count'] as int?,
        completedAt: json['completed_at'] != null
            ? DateTime.parse(json['completed_at'] as String)
            : null,
        errorLog: json['error_log'] as String?,
      );

  bool get isDone => status == 'done';
}

// ── System config (researcher-adjustable thresholds) ────────────

class SystemConfig {
  final double silenceThresholdDbfs;
  final double confidenceThreshold;
  final int rejectionThreshold;
  final String? updatedBy;
  final DateTime updatedAt;

  const SystemConfig({
    required this.silenceThresholdDbfs,
    required this.confidenceThreshold,
    required this.rejectionThreshold,
    this.updatedBy,
    required this.updatedAt,
  });

  factory SystemConfig.fromJson(Map<String, dynamic> j) => SystemConfig(
        silenceThresholdDbfs: (j['silence_threshold_dbfs'] as num).toDouble(),
        confidenceThreshold: (j['confidence_threshold'] as num).toDouble(),
        rejectionThreshold: j['rejection_threshold'] as int,
        updatedBy: j['updated_by'] as String?,
        updatedAt: DateTime.parse(j['updated_at']),
      );
}

// ── Admin: user management ───────────────────────────────────────

class AdminUser {
  final String id;
  final String email;
  final String? displayName;
  final String role;
  final bool isActive;
  final DateTime? deactivatedAt;
  final DateTime createdAt;
  final int recordingsCount;
  final int segmentsCount;

  const AdminUser({
    required this.id,
    required this.email,
    this.displayName,
    required this.role,
    required this.isActive,
    this.deactivatedAt,
    required this.createdAt,
    required this.recordingsCount,
    required this.segmentsCount,
  });

  factory AdminUser.fromJson(Map<String, dynamic> j) => AdminUser(
        id: j['id'],
        email: j['email'],
        displayName: j['display_name'],
        role: j['role'],
        isActive: j['is_active'] ?? true,
        deactivatedAt: j['deactivated_at'] != null
            ? DateTime.parse(j['deactivated_at'])
            : null,
        createdAt: DateTime.parse(j['created_at']),
        recordingsCount: j['recordings_count'] ?? 0,
        segmentsCount: j['segments_count'] ?? 0,
      );

  String get name => displayName ?? email.split('@').first;
}

class AdminSegment {
  final String id;
  final String recordingId;
  final String? uploaderDisplayName;
  final String uploaderEmail;
  final String reviewStatus;
  final String? effectiveLabel;
  final int? sequenceNum;
  final DateTime createdAt;

  const AdminSegment({
    required this.id,
    required this.recordingId,
    this.uploaderDisplayName,
    required this.uploaderEmail,
    required this.reviewStatus,
    this.effectiveLabel,
    this.sequenceNum,
    required this.createdAt,
  });

  factory AdminSegment.fromJson(Map<String, dynamic> j) => AdminSegment(
        id: j['id'],
        recordingId: j['recording_id'],
        uploaderDisplayName: j['uploader_display_name'],
        uploaderEmail: j['uploader_email'],
        reviewStatus: j['review_status'],
        effectiveLabel: j['effective_label'],
        sequenceNum: j['sequence_num'] as int?,
        createdAt: DateTime.parse(j['created_at']),
      );

  String get uploaderName =>
      uploaderDisplayName ?? uploaderEmail.split('@').first;
}

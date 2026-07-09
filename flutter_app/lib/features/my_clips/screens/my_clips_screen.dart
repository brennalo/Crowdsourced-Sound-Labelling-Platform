import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import '../../../core/api/providers.dart';
import '../../../core/models/models.dart';

// Filter tabs mapping to review_status values (null = all)
const _tabs = [
  (label: 'All',          status: null),
  (label: 'Needs Label',  status: 'annotation_pending'),
  (label: 'Needs Review', status: 'suggestion_pending'),
  (label: 'In Pool',      status: 'training_pool'),
  (label: 'Disputed',     status: 'consensus_open'),
  (label: 'Other',        status: 'excluded_other'),
];

class MyClipsScreen extends ConsumerStatefulWidget {
  const MyClipsScreen({super.key});

  @override
  ConsumerState<MyClipsScreen> createState() => _MyClipsScreenState();
}

class _MyClipsScreenState extends ConsumerState<MyClipsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  final _player = AudioPlayer();
  String? _playingId;

  // Per-segment UI state
  final Map<String, bool> _processing = {};
  final Map<String, String?> _pendingLabel = {}; // for annotation_pending: chosen label before submit

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _player.dispose();
    super.dispose();
  }

  // ── Audio ──────────────────────────────────────────────────

  Future<void> _togglePlay(String segmentId) async {
    if (_playingId == segmentId) {
      await _player.stop();
      setState(() => _playingId = null);
      return;
    }
    setState(() => _playingId = segmentId);
    try {
      final url = await ref.read(segmentServiceProvider).getAudioUrl(segmentId);
      await _player.setUrl(url);
      await _player.play();
      await _player.playerStateStream
          .firstWhere((s) => s.processingState == ProcessingState.completed);
    } catch (e) {
      _snack('Playback error: $e');
    } finally {
      if (mounted) setState(() => _playingId = null);
    }
  }

  // ── Label submission (annotation_pending) ──────────────────

  Future<void> _submitManualLabel(String segmentId, String label) async {
    setState(() => _processing[segmentId] = true);
    try {
      await ref.read(segmentServiceProvider).updateOwnLabel(segmentId, label);
      setState(() => _pendingLabel.remove(segmentId));
      _invalidateAll();
      if (label == 'other') _snack('Segment excluded — you can re-label it anytime.');
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _processing[segmentId] = false);
    }
  }

  // ── Suggestion review (suggestion_pending) ─────────────────

  Future<void> _accept(String segmentId) async {
    setState(() => _processing[segmentId] = true);
    try {
      await ref.read(suggestionServiceProvider).reviewSuggestion(
            segmentId: segmentId,
            decision: 'accepted',
          );
      _invalidateAll();
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _processing[segmentId] = false);
    }
  }

  Future<void> _reject(String segmentId, String correctedLabel) async {
    setState(() => _processing[segmentId] = true);
    try {
      await ref.read(suggestionServiceProvider).reviewSuggestion(
            segmentId: segmentId,
            decision: 'rejected',
            correctedLabel: correctedLabel,
          );
      _invalidateAll();
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _processing[segmentId] = false);
    }
  }

  void _invalidateAll() {
    ref.invalidate(allMySegmentsProvider);
    for (final t in _tabs) {
      if (t.status != null) ref.invalidate(mySegmentsProvider(t.status!));
    }
    ref.invalidate(suggestionQueueProvider);
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  // ── Reject bottom sheet — pick correct label ───────────────

  Future<void> _showRejectSheet(String segmentId) async {
    final labels = await ref.read(labelsProvider.future);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (_) => _LabelPickerSheet(
        title: 'Select correct label',
        labels: labels,
        includeOther: false,
        onSelect: (label) {
          Navigator.pop(context);
          _reject(segmentId, label);
        },
      ),
    );
  }

  // ── Edit own label bottom sheet (training_pool / excluded_other) ──

  Future<void> _showEditSheet(String segmentId) async {
    final labels = await ref.read(labelsProvider.future);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (_) => _LabelPickerSheet(
        title: 'Change label',
        labels: labels,
        includeOther: true,
        onSelect: (label) {
          Navigator.pop(context);
          _submitManualLabel(segmentId, label);
        },
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Clips'),
        bottom: TabBar(
          controller: _tabCtrl,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: _tabs.map((t) => Tab(text: t.label)).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: _tabs.map((t) => _TabContent(
              reviewStatus: t.status,
              playingId: _playingId,
              processing: _processing,
              pendingLabel: _pendingLabel,
              onPlay: _togglePlay,
              onLabelSelect: (segId, lbl) => setState(() => _pendingLabel[segId] = lbl),
              onSubmitLabel: _submitManualLabel,
              onAccept: _accept,
              onShowRejectSheet: _showRejectSheet,
              onShowEditSheet: _showEditSheet,
            )).toList(),
      ),
    );
  }
}

// ── Tab content ───────────────────────────────────────────────

class _TabContent extends ConsumerWidget {
  final String? reviewStatus;
  final String? playingId;
  final Map<String, bool> processing;
  final Map<String, String?> pendingLabel;
  final ValueChanged<String> onPlay;
  final void Function(String segId, String label) onLabelSelect;
  final void Function(String segId, String label) onSubmitLabel;
  final ValueChanged<String> onAccept;
  final ValueChanged<String> onShowRejectSheet;
  final ValueChanged<String> onShowEditSheet;

  const _TabContent({
    required this.reviewStatus,
    required this.playingId,
    required this.processing,
    required this.pendingLabel,
    required this.onPlay,
    required this.onLabelSelect,
    required this.onSubmitLabel,
    required this.onAccept,
    required this.onShowRejectSheet,
    required this.onShowEditSheet,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = reviewStatus == null
        ? ref.watch(allMySegmentsProvider)
        : ref.watch(mySegmentsProvider(reviewStatus!));

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (segments) {
        if (segments.isEmpty) {
          return const Center(
            child: Text('No clips here yet.', style: TextStyle(color: Colors.grey)),
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            if (reviewStatus == null) {
              ref.invalidate(allMySegmentsProvider);
            } else {
              ref.invalidate(mySegmentsProvider(reviewStatus!));
            }
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: segments.length,
            itemBuilder: (_, i) => _SegmentCard(
              segment: segments[i],
              isPlaying: playingId == segments[i].id,
              isProcessing: processing[segments[i].id] ?? false,
              selectedLabel: pendingLabel[segments[i].id],
              onPlay: () => onPlay(segments[i].id),
              onLabelSelect: (lbl) => onLabelSelect(segments[i].id, lbl),
              onSubmitLabel: (lbl) => onSubmitLabel(segments[i].id, lbl),
              onAccept: () => onAccept(segments[i].id),
              onReject: () => onShowRejectSheet(segments[i].id),
              onEdit: () => onShowEditSheet(segments[i].id),
            ),
          ),
        );
      },
    );
  }
}

// ── Segment card ──────────────────────────────────────────────

class _SegmentCard extends ConsumerWidget {
  final Segment segment;
  final bool isPlaying;
  final bool isProcessing;
  final String? selectedLabel;
  final VoidCallback onPlay;
  final void Function(String) onLabelSelect;
  final void Function(String) onSubmitLabel;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onEdit;

  const _SegmentCard({
    required this.segment,
    required this.isPlaying,
    required this.isProcessing,
    this.selectedLabel,
    required this.onPlay,
    required this.onLabelSelect,
    required this.onSubmitLabel,
    required this.onAccept,
    required this.onReject,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final labelsAsync = ref.watch(labelsProvider);
    final labels = labelsAsync.valueOrNull ?? [];

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ────────────────────────────────────
            Row(
              children: [
                IconButton.filledTonal(
                  onPressed: onPlay,
                  icon: Icon(isPlaying ? Icons.stop : Icons.play_arrow, size: 20),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 8),
                Text(
                  '${segment.startSec.toStringAsFixed(1)}s – ${segment.endSec.toStringAsFixed(1)}s',
                  style: theme.textTheme.bodyMedium,
                ),
                const Spacer(),
                _StatusBadge(segment: segment),
              ],
            ),

            // ── Model prediction row (shown when relevant) ────
            if (segment.modelLabel != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('Model: ', style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  )),
                  _LabelChip(label: segment.modelLabel!),
                  if (segment.modelConfidence != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${(segment.modelConfidence! * 100).toStringAsFixed(1)}%',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: _confColor(segment.modelConfidence!),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ],

            // ── Effective label (in pool / excluded) ──────────
            if (segment.effectiveLabel != null && !segment.needsAction) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Text('Label: ', style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  )),
                  _LabelChip(label: segment.effectiveLabel!),
                  const Spacer(),
                  // Own segments can always be directly edited
                  TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 10),

            // ── Action area ───────────────────────────────────
            if (isProcessing)
              const Center(child: CircularProgressIndicator())
            else if (segment.isAnnotationPending)
              _AnnotationActions(
                labels: labels,
                selectedLabel: selectedLabel,
                onSelect: onLabelSelect,
                onSubmit: onSubmitLabel,
              )
            else if (segment.isSuggestionPending)
              _SuggestionActions(onAccept: onAccept, onReject: onReject),
          ],
        ),
      ),
    );
  }

  Color _confColor(double c) {
    if (c >= 0.85) return Colors.green;
    if (c >= 0.75) return Colors.orange;
    return Colors.red;
  }
}

// ── Annotation_pending actions: label picker + submit ─────────

class _AnnotationActions extends ConsumerWidget {
  final List<AppLabel> labels;
  final String? selectedLabel;
  final void Function(String) onSelect;
  final void Function(String) onSubmit;

  const _AnnotationActions({
    required this.labels,
    required this.selectedLabel,
    required this.onSelect,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final allChoices = [...labels, AppLabel(id: 'other', name: 'other', displayName: 'Other')];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: allChoices.map((lbl) {
            final selected = selectedLabel == lbl.name;
            return ChoiceChip(
              label: Text(lbl.displayName),
              selected: selected,
              onSelected: (_) => onSelect(lbl.name),
            );
          }).toList(),
        ),
        if (selectedLabel != null) ...[
          const SizedBox(height: 10),
          FilledButton(
            onPressed: () => onSubmit(selectedLabel!),
            child: Text(selectedLabel == 'other' ? 'Exclude (other)' : 'Confirm Label'),
          ),
        ],
      ],
    );
  }
}

// ── Suggestion_pending actions: accept or reject+correct ──────

class _SuggestionActions extends StatelessWidget {
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _SuggestionActions({required this.onAccept, required this.onReject});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
              side: BorderSide(color: theme.colorScheme.error),
            ),
            onPressed: onReject,
            icon: const Icon(Icons.close, size: 18),
            label: const Text('Reject'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            onPressed: onAccept,
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Accept'),
          ),
        ),
      ],
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final Segment segment;
  const _StatusBadge({required this.segment});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (text, color) = switch (segment.reviewStatus) {
      'annotation_pending' => ('Needs Label', theme.colorScheme.error),
      'suggestion_pending' => ('Needs Review', Colors.orange),
      'training_pool' => ('In Pool', Colors.green),
      'consensus_open' => ('Disputed', Colors.purple),
      'excluded_other' => ('Other', theme.colorScheme.outline),
      _ => (segment.reviewStatus, theme.colorScheme.outline),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

class _LabelChip extends StatelessWidget {
  final String label;
  const _LabelChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isChainsaw = label == 'chainsaw';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isChainsaw
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isChainsaw ? Icons.warning_amber_outlined : Icons.forest_outlined,
            size: 14,
            color: isChainsaw
                ? theme.colorScheme.onErrorContainer
                : theme.colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isChainsaw
                  ? theme.colorScheme.onErrorContainer
                  : theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bottom sheet label picker ─────────────────────────────────

class _LabelPickerSheet extends StatelessWidget {
  final String title;
  final List<AppLabel> labels;
  final bool includeOther;
  final void Function(String) onSelect;

  const _LabelPickerSheet({
    required this.title,
    required this.labels,
    required this.includeOther,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final choices = [
      ...labels,
      if (includeOther) AppLabel(id: 'other', name: 'other', displayName: 'Other (exclude)'),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            ...choices.map((lbl) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    lbl.name == 'chainsaw'
                        ? Icons.warning_amber_outlined
                        : lbl.name == 'other'
                            ? Icons.help_outline
                            : Icons.forest_outlined,
                  ),
                  title: Text(lbl.displayName),
                  onTap: () => onSelect(lbl.name),
                )),
          ],
        ),
      ),
    );
  }
}

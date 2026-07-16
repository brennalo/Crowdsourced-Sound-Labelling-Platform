import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import '../../../core/api/providers.dart';
import '../../../core/models/models.dart';
import '../../../app/theme.dart';

const _tabs = [
  (label: 'All', status: null),
  (label: 'Needs Label', status: 'annotation_pending'),
  (label: 'Needs Review', status: 'suggestion_pending'),
  (label: 'In Pool', status: 'training_pool'),
  (label: 'Disputed', status: 'consensus_open'),
  (label: 'Other', status: 'excluded_other'),
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
  bool _groupedView = false;

  final Map<String, bool> _processing = {};
  final Map<String, String?> _pendingLabel = {};

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

  Future<void> _submitManualLabel(String segmentId, String label) async {
    setState(() => _processing[segmentId] = true);
    try {
      await ref.read(segmentServiceProvider).updateOwnLabel(segmentId, label);
      setState(() => _pendingLabel.remove(segmentId));
      _invalidateAll();
      if (label == 'other')
        _snack('Segment excluded — you can re-label it anytime.');
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _processing[segmentId] = false);
    }
  }

  Future<void> _accept(String segmentId) async {
    setState(() => _processing[segmentId] = true);
    try {
      await ref
          .read(suggestionServiceProvider)
          .reviewSuggestion(segmentId: segmentId, decision: 'accepted');
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
          correctedLabel: correctedLabel);
      _invalidateAll();
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _processing[segmentId] = false);
    }
  }

  void _invalidateAll() {
    ref.invalidate(allMySegmentsProvider);
    ref.invalidate(myRecordingsProvider);
    for (final t in _tabs) {
      if (t.status != null) ref.invalidate(mySegmentsProvider(t.status!));
    }
    ref.invalidate(suggestionQueueProvider);
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _showRejectSheet(String segmentId) async {
    final labels = await ref.read(labelsProvider.future);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (_) => _LabelPickerSheet(
        title: 'Select correct label',
        labels: labels,
        includeOther: false,
        onSelect: (l) {
          Navigator.pop(context);
          _reject(segmentId, l);
        },
      ),
    );
  }

  Future<void> _showEditSheet(String segmentId) async {
    final labels = await ref.read(labelsProvider.future);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (_) => _LabelPickerSheet(
        title: 'Change label',
        labels: labels,
        includeOther: true,
        onSelect: (l) {
          Navigator.pop(context);
          _submitManualLabel(segmentId, l);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Clips'),
        actions: [
          IconButton(
            tooltip:
                _groupedView ? 'Switch to flat list' : 'Group by recording',
            icon: Icon(_groupedView ? Icons.view_list : Icons.folder_outlined),
            onPressed: () => setState(() => _groupedView = !_groupedView),
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: _tabs.map((t) => Tab(text: t.label)).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: _tabs.map((t) {
          final sharedProps = _SharedProps(
            reviewStatus: t.status,
            playingId: _playingId,
            processing: _processing,
            pendingLabel: _pendingLabel,
            onPlay: _togglePlay,
            onLabelSelect: (id, lbl) => setState(() => _pendingLabel[id] = lbl),
            onSubmitLabel: _submitManualLabel,
            onAccept: _accept,
            onShowRejectSheet: _showRejectSheet,
            onShowEditSheet: _showEditSheet,
          );
          return _groupedView
              ? _GroupedTabContent(props: sharedProps)
              : _FlatTabContent(props: sharedProps);
        }).toList(),
      ),
    );
  }
}

// ── Shared props bundle to avoid long constructor chains ──────

class _SharedProps {
  final String? reviewStatus;
  final String? playingId;
  final Map<String, bool> processing;
  final Map<String, String?> pendingLabel;
  final ValueChanged<String> onPlay;
  final void Function(String, String) onLabelSelect;
  final void Function(String, String) onSubmitLabel;
  final ValueChanged<String> onAccept;
  final ValueChanged<String> onShowRejectSheet;
  final ValueChanged<String> onShowEditSheet;

  const _SharedProps({
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
}

// ═══════════════════════════════════════════════════════════════
//  Flat list view
// ═══════════════════════════════════════════════════════════════

class _FlatTabContent extends ConsumerWidget {
  final _SharedProps props;
  const _FlatTabContent({required this.props});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = props.reviewStatus == null
        ? ref.watch(allMySegmentsProvider)
        : ref.watch(mySegmentsProvider(props.reviewStatus!));

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (segments) {
        if (segments.isEmpty) return const _EmptyPlaceholder();
        return RefreshIndicator(
          onRefresh: () async {
            props.reviewStatus == null
                ? ref.invalidate(allMySegmentsProvider)
                : ref.invalidate(mySegmentsProvider(props.reviewStatus!));
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: segments.length,
            itemBuilder: (_, i) => SegmentCard(
              segment: segments[i],
              isPlaying: props.playingId == segments[i].id,
              isProcessing: props.processing[segments[i].id] ?? false,
              selectedLabel: props.pendingLabel[segments[i].id],
              onPlay: () => props.onPlay(segments[i].id),
              onLabelSelect: (l) => props.onLabelSelect(segments[i].id, l),
              onSubmitLabel: (l) => props.onSubmitLabel(segments[i].id, l),
              onAccept: () => props.onAccept(segments[i].id),
              onReject: () => props.onShowRejectSheet(segments[i].id),
              onEdit: () => props.onShowEditSheet(segments[i].id),
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  Grouped view — expandable cards per recording
// ═══════════════════════════════════════════════════════════════

class _GroupedTabContent extends ConsumerWidget {
  final _SharedProps props;
  const _GroupedTabContent({required this.props});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final segmentsAsync = props.reviewStatus == null
        ? ref.watch(allMySegmentsProvider)
        : ref.watch(mySegmentsProvider(props.reviewStatus!));
    final recordingsAsync = ref.watch(myRecordingsProvider);

    return segmentsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (segments) {
        if (segments.isEmpty) return const _EmptyPlaceholder();

        // Group by recordingId preserving order of first appearance
        final grouped = <String, List<Segment>>{};
        for (final seg in segments) {
          grouped.putIfAbsent(seg.recordingId, () => []).add(seg);
        }

        // Recording label map (date + time from recorded_at or created_at)
        final recLabels = <String, String>{};
        recordingsAsync.whenData((recs) {
          for (final r in recs) {
            final dt = r.recordedAt ?? r.createdAt;
            recLabels[r.id] =
                '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
                '${dt.day.toString().padLeft(2, '0')} '
                '${dt.hour.toString().padLeft(2, '0')}:'
                '${dt.minute.toString().padLeft(2, '0')}';
          }
        });

        final ids = grouped.keys.toList();

        return RefreshIndicator(
          onRefresh: () async {
            props.reviewStatus == null
                ? ref.invalidate(allMySegmentsProvider)
                : ref.invalidate(mySegmentsProvider(props.reviewStatus!));
            ref.invalidate(myRecordingsProvider);
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: ids.length,
            itemBuilder: (_, i) {
              final recId = ids[i];
              final segs = grouped[recId]!;
              final needsAction = segs.where((s) => s.needsAction).length;
              return _RecordingGroup(
                recordingLabel: recLabels[recId] ?? 'Recording ${i + 1}',
                segments: segs,
                needsActionCount: needsAction,
                props: props,
              );
            },
          ),
        );
      },
    );
  }
}

class _RecordingGroup extends StatefulWidget {
  final String recordingLabel;
  final List<Segment> segments;
  final int needsActionCount;
  final _SharedProps props;

  const _RecordingGroup({
    required this.recordingLabel,
    required this.segments,
    required this.needsActionCount,
    required this.props,
  });

  @override
  State<_RecordingGroup> createState() => _RecordingGroupState();
}

class _RecordingGroupState extends State<_RecordingGroup> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    // Auto-expand if any segment needs action
    _expanded = widget.needsActionCount > 0;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = widget.segments.length;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          // Header
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: _expanded
                ? const BorderRadius.vertical(top: Radius.circular(12))
                : BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.mic_outlined,
                      size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.recordingLabel,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        Text('$total segment${total == 1 ? '' : 's'}',
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: theme.colorScheme.outline)),
                      ],
                    ),
                  ),
                  if (widget.needsActionCount > 0)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.error,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('${widget.needsActionCount} to do',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onError)),
                    ),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                      color: theme.colorScheme.outline),
                ],
              ),
            ),
          ),

          // Segments
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: Column(
                children: widget.segments
                    .map((seg) => SegmentCard(
                          segment: seg,
                          isPlaying: widget.props.playingId == seg.id,
                          isProcessing:
                              widget.props.processing[seg.id] ?? false,
                          selectedLabel: widget.props.pendingLabel[seg.id],
                          compact: true,
                          onPlay: () => widget.props.onPlay(seg.id),
                          onLabelSelect: (l) =>
                              widget.props.onLabelSelect(seg.id, l),
                          onSubmitLabel: (l) =>
                              widget.props.onSubmitLabel(seg.id, l),
                          onAccept: () => widget.props.onAccept(seg.id),
                          onReject: () =>
                              widget.props.onShowRejectSheet(seg.id),
                          onEdit: () => widget.props.onShowEditSheet(seg.id),
                        ))
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  SegmentCard — shared between flat and grouped
// ═══════════════════════════════════════════════════════════════

class SegmentCard extends ConsumerWidget {
  final Segment segment;
  final bool isPlaying;
  final bool isProcessing;
  final String? selectedLabel;
  final bool compact;
  final VoidCallback onPlay;
  final void Function(String) onLabelSelect;
  final void Function(String) onSubmitLabel;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onEdit;

  const SegmentCard({
    super.key,
    required this.segment,
    required this.isPlaying,
    required this.isProcessing,
    this.selectedLabel,
    this.compact = false,
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
    final labels = ref.watch(labelsProvider).valueOrNull ?? [];

    return Container(
      margin: EdgeInsets.only(bottom: compact ? 6 : 10),
      decoration: BoxDecoration(
        color: compact ? theme.colorScheme.surfaceContainerLowest : null,
        borderRadius: BorderRadius.circular(compact ? 8 : 12),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 10.0 : 14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton.filledTonal(
                  onPressed: onPlay,
                  icon:
                      Icon(isPlaying ? Icons.stop : Icons.play_arrow, size: 18),
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
            if (segment.modelLabel != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Text('Model: ',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.outline)),
                  _LabelChip(label: segment.modelLabel!),
                  if (segment.modelConfidence != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${(segment.modelConfidence! * 100).toStringAsFixed(1)}%',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: _confColor(
                            segment.modelConfidence!, theme.colorScheme),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ],
            if (segment.effectiveLabel != null && !segment.needsAction) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Text('Label: ',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.outline)),
                  _LabelChip(label: segment.effectiveLabel!),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 14),
                    label: const Text('Edit'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            if (isProcessing)
              const Center(
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)))
            else if (segment.isAnnotationPending)
              _AnnotationActions(
                  labels: labels,
                  selectedLabel: selectedLabel,
                  onSelect: onLabelSelect,
                  onSubmit: onSubmitLabel)
            else if (segment.isSuggestionPending)
              _SuggestionActions(onAccept: onAccept, onReject: onReject),
          ],
        ),
      ),
    );
  }

  Color _confColor(double c, ColorScheme scheme) {
    if (c >= 0.85) return AppColors.canopy;
    if (c >= 0.75) return AppColors.amber;
    return scheme.error;
  }
}

// ── Small reusable widgets ────────────────────────────────────

class _AnnotationActions extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final choices = [
      ...labels,
      AppLabel(id: 'other', name: 'other', displayName: 'Other'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: choices
              .map((l) => ChoiceChip(
                    label: Text(l.displayName),
                    selected: selectedLabel == l.name,
                    onSelected: (_) => onSelect(l.name),
                  ))
              .toList(),
        ),
        if (selectedLabel != null) ...[
          const SizedBox(height: 10),
          FilledButton(
            onPressed: () => onSubmit(selectedLabel!),
            child: Text(
                selectedLabel == 'other' ? 'Exclude (other)' : 'Confirm Label'),
          ),
        ],
      ],
    );
  }
}

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
            style: FilledButton.styleFrom(backgroundColor: AppColors.canopy),
            onPressed: onAccept,
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Accept'),
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final Segment segment;
  const _StatusBadge({required this.segment});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (text, color) = switch (segment.reviewStatus) {
      'annotation_pending' => ('Needs Label', theme.colorScheme.error),
      'suggestion_pending' => ('Needs Review', AppColors.amber),
      'training_pool' => ('In Pool', AppColors.canopy),
      'consensus_open' => ('Disputed', AppColors.bark),
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
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: color)),
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
          Text(label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isChainsaw
                    ? theme.colorScheme.onErrorContainer
                    : theme.colorScheme.onPrimaryContainer,
              )),
        ],
      ),
    );
  }
}

class _EmptyPlaceholder extends StatelessWidget {
  const _EmptyPlaceholder();
  @override
  Widget build(BuildContext context) => Center(
        child: Text('No clips here yet.',
            style: TextStyle(color: Theme.of(context).colorScheme.outline)),
      );
}

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
      if (includeOther)
        AppLabel(id: 'other', name: 'other', displayName: 'Other (exclude)'),
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
            ...choices.map((l) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(l.name == 'chainsaw'
                      ? Icons.warning_amber_outlined
                      : l.name == 'other'
                          ? Icons.help_outline
                          : Icons.forest_outlined),
                  title: Text(l.displayName),
                  onTap: () => onSelect(l.name),
                )),
          ],
        ),
      ),
    );
  }
}

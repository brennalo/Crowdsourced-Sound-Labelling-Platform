import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import '../../../core/api/providers.dart';
import '../../../core/models/models.dart';
import '../../../../config.dart';

class AnnotateScreen extends ConsumerStatefulWidget {
  final String recordingId;
  const AnnotateScreen({super.key, required this.recordingId});

  @override
  ConsumerState<AnnotateScreen> createState() => _AnnotateScreenState();
}

class _AnnotateScreenState extends ConsumerState<AnnotateScreen> {
  final _player = AudioPlayer();
  String? _playingSegmentId;
  final Map<String, String> _pendingLabels =
      {}; // segmentId → label (before submit)
  final Set<String> _submitting = {};
  final Set<String> _submitted = {};

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _playSegment(String segmentId) async {
    if (_playingSegmentId == segmentId) {
      await _player.stop();
      setState(() => _playingSegmentId = null);
      return;
    }

    setState(() => _playingSegmentId = segmentId);
    try {
      final url = await ref.read(segmentServiceProvider).getAudioUrl(segmentId);
      await _player.setUrl(url);
      await _player.play();
      await _player.playerStateStream.firstWhere(
        (s) => s.processingState == ProcessingState.completed,
      );
    } catch (e) {
      if (mounted) _showSnack('Playback error: $e');
    } finally {
      if (mounted) setState(() => _playingSegmentId = null);
    }
  }

  Future<void> _submitLabel(String segmentId, String label) async {
    setState(() => _submitting.add(segmentId));
    try {
      await ref.read(annotationServiceProvider).annotateSegment(
            segmentId: segmentId,
            label: label,
          );
      setState(() {
        _submitted.add(segmentId);
        _pendingLabels.remove(segmentId);
      });
      ref.invalidate(recordingSegmentsProvider(widget.recordingId));
    } catch (e) {
      _showSnack('Failed: $e');
    } finally {
      setState(() => _submitting.remove(segmentId));
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final segmentsAsync =
        ref.watch(recordingSegmentsProvider(widget.recordingId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Annotate Segments')),
      body: segmentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (segments) {
          final pending = segments.where((s) => !s.isAnnotated).toList();
          final done = segments.where((s) => s.isAnnotated).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (pending.isNotEmpty) ...[
                Text('Needs Annotation (${pending.length})',
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                ...pending.map((s) => _SegmentCard(
                      segment: s,
                      isPlaying: _playingSegmentId == s.id,
                      isSubmitting: _submitting.contains(s.id),
                      isSubmitted: _submitted.contains(s.id),
                      selectedLabel: _pendingLabels[s.id],
                      onPlay: () => _playSegment(s.id),
                      onLabelSelect: (label) =>
                          setState(() => _pendingLabels[s.id] = label),
                      onSubmit: () {
                        final label = _pendingLabels[s.id];
                        if (label != null) _submitLabel(s.id, label);
                      },
                    )),
              ],
              if (done.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Annotated (${done.length})',
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                ...done.map((s) => _SegmentCard(
                      segment: s,
                      isPlaying: _playingSegmentId == s.id,
                      isSubmitting: false,
                      isSubmitted: true,
                      onPlay: () => _playSegment(s.id),
                    )),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SegmentCard extends StatelessWidget {
  final Segment segment;
  final bool isPlaying;
  final bool isSubmitting;
  final bool isSubmitted;
  final String? selectedLabel;
  final VoidCallback onPlay;
  final void Function(String)? onLabelSelect;
  final VoidCallback? onSubmit;

  const _SegmentCard({
    required this.segment,
    required this.isPlaying,
    required this.isSubmitting,
    required this.isSubmitted,
    this.selectedLabel,
    required this.onPlay,
    this.onLabelSelect,
    this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDone = isSubmitted || segment.isAnnotated;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: isDone ? theme.colorScheme.surfaceContainerLowest : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton.filledTonal(
                  onPressed: onPlay,
                  icon: Icon(isPlaying ? Icons.stop : Icons.play_arrow),
                ),
                const SizedBox(width: 8),
                Text(
                  '${segment.startSec.toStringAsFixed(1)}s – ${segment.endSec.toStringAsFixed(1)}s',
                  style: theme.textTheme.bodyMedium,
                ),
                const Spacer(),
                if (isDone)
                  Chip(
                    label: Text(segment.reviewStatus == 'annotated'
                        ? 'Done'
                        : 'Labelled'),
                    backgroundColor: theme.colorScheme.primaryContainer,
                    labelStyle: TextStyle(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontSize: 12),
                  ),
              ],
            ),
            if (!isDone) ...[
              const SizedBox(height: 12),
              Row(
                children: AppConfig.labels.map((label) {
                  final isSelected = selectedLabel == label;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: isSelected
                              ? theme.colorScheme.primaryContainer
                              : null,
                          side: BorderSide(
                            color: isSelected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outline,
                          ),
                        ),
                        onPressed: onLabelSelect != null
                            ? () => onLabelSelect!(label)
                            : null,
                        child: Text(
                          AppConfig.labelDisplayNames[label] ?? label,
                          style: TextStyle(
                              fontSize: 13,
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : null),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              if (selectedLabel != null) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: isSubmitting ? null : onSubmit,
                    child: isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Confirm Label'),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

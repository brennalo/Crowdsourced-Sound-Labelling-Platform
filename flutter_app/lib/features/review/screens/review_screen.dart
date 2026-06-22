import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import '../../../core/api/providers.dart';
import '../../../core/models/models.dart';
import '../../../../config.dart';

class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  final _player = AudioPlayer();
  String? _playingSegmentId;
  final Set<String> _processing = {};
  final Map<String, String> _decisions = {}; // segmentId → accepted/rejected

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

  Future<void> _submitReview(String segmentId, String decision) async {
    setState(() => _processing.add(segmentId));
    try {
      await ref.read(suggestionServiceProvider).reviewSuggestion(
            segmentId: segmentId,
            decision: decision,
          );
      setState(() => _decisions[segmentId] = decision);
      ref.invalidate(suggestionQueueProvider);
    } catch (e) {
      _showSnack('Error: $e');
    } finally {
      setState(() => _processing.remove(segmentId));
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final queueAsync = ref.watch(suggestionQueueProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Suggestions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(suggestionQueueProvider),
          ),
        ],
      ),
      body: queueAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (segments) {
          final reviewable =
              segments.where((s) => !_decisions.containsKey(s.id)).toList();

          if (reviewable.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 64, color: theme.colorScheme.primary),
                  const SizedBox(height: 16),
                  Text('All caught up!', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    'No segments need review right now.\nNew ones will appear as recordings are processed.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh'),
                    onPressed: () => ref.invalidate(suggestionQueueProvider),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              _InfoBanner(count: reviewable.length),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: reviewable.length,
                  itemBuilder: (context, i) => _SuggestionCard(
                    segment: reviewable[i],
                    isPlaying: _playingSegmentId == reviewable[i].id,
                    isProcessing: _processing.contains(reviewable[i].id),
                    onPlay: () => _playSegment(reviewable[i].id),
                    onAccept: () => _submitReview(reviewable[i].id, 'accepted'),
                    onReject: () => _submitReview(reviewable[i].id, 'rejected'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final int count;
  const _InfoBanner({required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHigh,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(
        '$count segment${count == 1 ? '' : 's'} awaiting review. '
        'Listen to each clip and verify the AI\'s prediction.',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  final Segment segment;
  final bool isPlaying;
  final bool isProcessing;
  final VoidCallback onPlay;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _SuggestionCard({
    required this.segment,
    required this.isPlaying,
    required this.isProcessing,
    required this.onPlay,
    required this.onAccept,
    required this.onReject,
  });

  Color _confidenceColor(BuildContext context, double confidence) {
    if (confidence >= 0.85) return Colors.green;
    if (confidence >= 0.70) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = segment.predictedLabel ?? 'unknown';
    final confidence = segment.confidence ?? 0.0;
    final displayLabel = AppConfig.labelDisplayNames[label] ?? label;
    final confColor = _confidenceColor(context, confidence);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: play + time range
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
              ],
            ),
            const SizedBox(height: 12),

            // Prediction row
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: label == 'chainsaw'
                        ? theme.colorScheme.errorContainer
                        : theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        label == 'chainsaw'
                            ? Icons.warning_amber_outlined
                            : Icons.forest_outlined,
                        size: 16,
                        color: label == 'chainsaw'
                            ? theme.colorScheme.onErrorContainer
                            : theme.colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        displayLabel,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: label == 'chainsaw'
                              ? theme.colorScheme.onErrorContainer
                              : theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Confidence',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: theme.colorScheme.outline)),
                    Text(
                      '${(confidence * 100).toStringAsFixed(1)}%',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: confColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                SizedBox(
                  width: 80,
                  child: LinearProgressIndicator(
                    value: confidence,
                    color: confColor,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Accept / Reject buttons
            if (isProcessing)
              const Center(child: CircularProgressIndicator())
            else
              Row(
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
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: onAccept,
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Accept'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

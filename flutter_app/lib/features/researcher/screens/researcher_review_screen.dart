import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import '../../../core/api/providers.dart';
import '../../../core/models/models.dart';

class ResearcherReviewScreen extends ConsumerStatefulWidget {
  const ResearcherReviewScreen({super.key});

  @override
  ConsumerState<ResearcherReviewScreen> createState() =>
      _ResearcherReviewScreenState();
}

class _ResearcherReviewScreenState extends ConsumerState<ResearcherReviewScreen> {
  final _player = AudioPlayer();
  String? _playingId;

  // Local queue mirrors the server queue.
  // Reviewed items are removed immediately; new ones fetched to top up.
  List<Segment> _queue = [];
  bool _loadingQueue = true;
  final Set<String> _processing = {};

  @override
  void initState() {
    super.initState();
    _loadQueue();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _loadQueue() async {
    setState(() => _loadingQueue = true);
    try {
      final segments = await ref.read(researcherServiceProvider).getReviewQueue();
      setState(() => _queue = segments);
    } catch (e) {
      _snack('Error loading queue: $e');
    } finally {
      if (mounted) setState(() => _loadingQueue = false);
    }
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

  Future<void> _confirm(String segmentId) async {
    setState(() => _processing.add(segmentId));
    try {
      await ref.read(researcherServiceProvider)
          .submitReview(segmentId: segmentId, action: 'confirmed');
      _removeAndRefresh(segmentId);
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _processing.remove(segmentId));
    }
  }

  Future<void> _showCorrectSheet(String segmentId) async {
    final labels = await ref.read(labelsProvider.future);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (_) => _CorrectSheet(
        labels: labels,
        onSelect: (label) async {
          Navigator.pop(context);
          await _correct(segmentId, label);
        },
      ),
    );
  }

  Future<void> _correct(String segmentId, String correctedLabel) async {
    setState(() => _processing.add(segmentId));
    try {
      await ref.read(researcherServiceProvider).submitReview(
            segmentId: segmentId,
            action: 'corrected',
            correctedLabel: correctedLabel,
          );
      _removeAndRefresh(segmentId);
      _snack('Label corrected to "$correctedLabel"');
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _processing.remove(segmentId));
    }
  }

  /// Removes reviewed segment locally, then fetches 1 replacement.
  Future<void> _removeAndRefresh(String segmentId) async {
    setState(() => _queue.removeWhere((s) => s.id == segmentId));
    // Quietly top up — fetch a fresh queue and add unseen items
    try {
      final fresh = await ref.read(researcherServiceProvider).getReviewQueue();
      final existingIds = _queue.map((s) => s.id).toSet();
      final newItems = fresh.where((s) => !existingIds.contains(s.id)).toList();
      if (mounted && newItems.isNotEmpty) {
        setState(() => _queue.addAll(newItems));
      }
    } catch (_) {
      // Silent — queue still works with existing items
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Queue'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadQueue),
        ],
      ),
      body: _loadingQueue
          ? const Center(child: CircularProgressIndicator())
          : _queue.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 64, color: theme.colorScheme.primary),
                      const SizedBox(height: 16),
                      Text('All caught up!', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text('No unreviewed segments in the training pool.',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: theme.colorScheme.outline)),
                      const SizedBox(height: 24),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: const Text('Refresh'),
                        onPressed: _loadQueue,
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Container(
                      width: double.infinity,
                      color: theme.colorScheme.surfaceContainerHigh,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Text(
                        '${_queue.length} randomly sampled segment${_queue.length == 1 ? '' : 's'}. '
                        'Confirm correct labels or correct wrong ones.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _queue.length,
                        itemBuilder: (_, i) => _ReviewCard(
                          segment: _queue[i],
                          isPlaying: _playingId == _queue[i].id,
                          isProcessing: _processing.contains(_queue[i].id),
                          onPlay: () => _togglePlay(_queue[i].id),
                          onConfirm: () => _confirm(_queue[i].id),
                          onCorrect: () => _showCorrectSheet(_queue[i].id),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final Segment segment;
  final bool isPlaying;
  final bool isProcessing;
  final VoidCallback onPlay;
  final VoidCallback onConfirm;
  final VoidCallback onCorrect;

  const _ReviewCard({
    required this.segment,
    required this.isPlaying,
    required this.isProcessing,
    required this.onPlay,
    required this.onConfirm,
    required this.onCorrect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = segment.effectiveLabel ?? 'unknown';
    final isChainsaw = label == 'chainsaw';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton.filledTonal(
                  onPressed: onPlay,
                  icon: Icon(isPlaying ? Icons.stop : Icons.play_arrow),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 8),
                Text(
                  '${segment.startSec.toStringAsFixed(1)}s – ${segment.endSec.toStringAsFixed(1)}s',
                  style: theme.textTheme.bodyMedium,
                ),
                const Spacer(),
                Text(
                  segment.poolEntryReason == 'auto_7day'
                      ? 'auto-accepted'
                      : segment.poolEntryReason ?? '',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text('Label: ',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.outline)),
                Container(
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
                ),
                if (segment.modelConfidence != null) ...[
                  const SizedBox(width: 12),
                  Text(
                    '${(segment.modelConfidence! * 100).toStringAsFixed(1)}% confidence',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
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
                      onPressed: onCorrect,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Correct'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: Colors.green),
                      onPressed: onConfirm,
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Confirm'),
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

class _CorrectSheet extends StatelessWidget {
  final List<AppLabel> labels;
  final void Function(String) onSelect;

  const _CorrectSheet({required this.labels, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Correct label to…', style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            ...labels.map((lbl) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(lbl.name == 'chainsaw'
                      ? Icons.warning_amber_outlined
                      : Icons.forest_outlined),
                  title: Text(lbl.displayName),
                  onTap: () => onSelect(lbl.name),
                )),
          ],
        ),
      ),
    );
  }
}

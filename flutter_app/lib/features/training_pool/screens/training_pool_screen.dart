import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import '../../../core/api/providers.dart';
import '../../../core/models/models.dart';
import '../../../core/widgets/account_menu_button.dart';
import '../../../app/theme.dart';

class TrainingPoolScreen extends ConsumerStatefulWidget {
  const TrainingPoolScreen({super.key});

  @override
  ConsumerState<TrainingPoolScreen> createState() => _TrainingPoolScreenState();
}

class _TrainingPoolScreenState extends ConsumerState<TrainingPoolScreen> {
  final _player = AudioPlayer();
  String? _playingId;
  String _sort = 'time_desc';
  final Set<String> _actioning = {};
  final Set<String> _reported = {};
  final Set<String> _pickingFor = {};

  @override
  void dispose() {
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

  // ── Contributor: report segment (open consensus) ──────────
  // Instead of a dialog, "Report Wrong Label" expands the card in place
  // into a chip picker. Tapping a chip submits the report directly.

  void _togglePicker(String segmentId) {
    setState(() {
      if (_pickingFor.contains(segmentId)) {
        _pickingFor.remove(segmentId);
      } else {
        _pickingFor.add(segmentId);
      }
    });
  }

  Future<void> _submitReport(Segment segment, String proposedLabel) async {
    setState(() {
      _pickingFor.remove(segment.id);
      _actioning.add(segment.id);
    });
    try {
      await ref
          .read(consensusServiceProvider)
          .reportSegment(segment.id, proposedLabel);
      setState(() => _reported.add(segment.id));
      ref.invalidate(trainingPoolProvider(_sort));
      _snack('Reported — segment is now open for consensus voting.');
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _actioning.remove(segment.id));
    }
  }

  // ── Researcher: direct override ───────────────────────────

  Future<void> _showOverrideSheet(String segmentId) async {
    final labels = await ref.read(labelsProvider.future);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (_) => _OverrideSheet(
        labels: labels,
        onSelect: (label) async {
          Navigator.pop(context);
          await _submitOverride(segmentId, label);
        },
      ),
    );
  }

  Future<void> _submitOverride(String segmentId, String label) async {
    setState(() => _actioning.add(segmentId));
    try {
      await ref.read(researcherServiceProvider).submitReview(
            segmentId: segmentId,
            action: 'corrected',
            correctedLabel: label,
          );
      ref.invalidate(trainingPoolProvider(_sort));
      _snack('Label overridden to "$label"');
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _actioning.remove(segmentId));
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isResearcher = ref.watch(authProvider).isResearcher;
    final poolAsync = ref.watch(trainingPoolProvider(_sort));
    final labelsAsync = ref.watch(labelsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Training Pool'),
        actions: [
          // Sort dropdown
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort',
            initialValue: _sort,
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'time_desc', child: Text('Newest first')),
              PopupMenuItem(value: 'time_asc', child: Text('Oldest first')),
              PopupMenuItem(
                  value: 'confidence_desc',
                  child: Text('High confidence first')),
              PopupMenuItem(
                  value: 'confidence_asc', child: Text('Low confidence first')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(trainingPoolProvider(_sort)),
          ),
          const SizedBox(width: 4),
          const AccountMenuButton(),
          const SizedBox(width: 8),
        ],
      ),
      body: poolAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (segments) {
          if (segments.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.dataset_outlined,
                      size: 64, color: theme.colorScheme.outline),
                  const SizedBox(height: 16),
                  Text('Training pool is empty',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                      'Segments appear here once contributors label or accept clips.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.outline)),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(trainingPoolProvider(_sort)),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: segments.length,
              itemBuilder: (_, i) => _PoolCard(
                segment: segments[i],
                isPlaying: _playingId == segments[i].id,
                isActioning: _actioning.contains(segments[i].id),
                alreadyReported: _reported.contains(segments[i].id),
                isResearcher: isResearcher,
                showPicker: _pickingFor.contains(segments[i].id),
                labelsAsync: labelsAsync,
                onPlay: () => _togglePlay(segments[i].id),
                onToggleReport: () => _togglePicker(segments[i].id),
                onCancelPicker: () => _togglePicker(segments[i].id),
                onSelectLabel: (label) => _submitReport(segments[i], label),
                onOverride: () => _showOverrideSheet(segments[i].id),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PoolCard extends StatelessWidget {
  final Segment segment;
  final bool isPlaying;
  final bool isActioning;
  final bool alreadyReported;
  final bool isResearcher;
  final bool showPicker;
  final AsyncValue<List<AppLabel>> labelsAsync;
  final VoidCallback onPlay;
  final VoidCallback onToggleReport;
  final VoidCallback onCancelPicker;
  final void Function(String label) onSelectLabel;
  final VoidCallback onOverride;

  const _PoolCard({
    required this.segment,
    required this.isPlaying,
    required this.isActioning,
    required this.alreadyReported,
    required this.isResearcher,
    required this.showPicker,
    required this.labelsAsync,
    required this.onPlay,
    required this.onToggleReport,
    required this.onCancelPicker,
    required this.onSelectLabel,
    required this.onOverride,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = segment.effectiveLabel ?? 'unknown';
    final isChainsaw = label == 'chainsaw';
    final uploaderName = segment.uploaderDisplayName ?? 'contributor';
    final reason = segment.poolEntryReason ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Audio row
            Row(
              children: [
                IconButton.filledTonal(
                  onPressed: onPlay,
                  icon: Icon(isPlaying ? Icons.stop : Icons.play_arrow),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    segment.displayLabel,
                    style: theme.textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                if (segment.consensusOpen) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.bark.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('Disputed',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.bark)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),

            // Label + meta
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                        isChainsaw
                            ? Icons.warning_amber_outlined
                            : Icons.forest_outlined,
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
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'by $uploaderName · ${_reasonLabel(reason)}',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.outline),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),

            // Confidence
            if (segment.modelConfidence != null) ...[
              const SizedBox(height: 4),
              Text(
                'Model confidence: ${(segment.modelConfidence! * 100).toStringAsFixed(1)}%',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],

            const SizedBox(height: 12),

            // Action button
            if (isActioning)
              const Center(child: CircularProgressIndicator())
            else if (isResearcher)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    side: BorderSide(color: theme.colorScheme.error),
                  ),
                  onPressed: onOverride,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Override Label'),
                ),
              )
            else if (showPicker)
              _LabelPicker(
                segment: segment,
                labelsAsync: labelsAsync,
                onSelect: onSelectLabel,
                onCancel: onCancelPicker,
              )
            else
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.bark,
                    side: const BorderSide(color: AppColors.bark),
                  ),
                  onPressed: alreadyReported || segment.consensusOpen
                      ? null
                      : onToggleReport,
                  icon: const Icon(Icons.flag_outlined, size: 18),
                  label: Text(segment.consensusOpen
                      ? 'Already Disputed'
                      : alreadyReported
                          ? 'Reported'
                          : 'Report Wrong Label'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _reasonLabel(String reason) {
    return switch (reason) {
      'accepted' => 'AI accepted',
      'manual' => 'manually labelled',
      'auto_7day' => 'auto-accepted',
      _ => reason,
    };
  }
}

/// Inline chip picker shown in place of the "Report Wrong Label" button.
/// Tapping a chip submits the report immediately (no separate confirm step);
/// tapping Cancel collapses back to the button. Deliberately not a
/// dialog/bottom sheet — keeps everything on the same route so there's no
/// second Navigator involved.
class _LabelPicker extends StatelessWidget {
  final Segment segment;
  final AsyncValue<List<AppLabel>> labelsAsync;
  final void Function(String label) onSelect;
  final VoidCallback onCancel;

  const _LabelPicker({
    required this.segment,
    required this.labelsAsync,
    required this.onSelect,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What should this be?',
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
        const SizedBox(height: 8),
        labelsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          error: (e, _) => Text(
            'Failed to load labels',
            style: TextStyle(color: theme.colorScheme.error),
          ),
          data: (labels) {
            final choices =
                labels.where((l) => l.name != segment.effectiveLabel).toList();
            if (choices.isEmpty) {
              return Text(
                'No other active labels available.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              );
            }
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...choices.map(
                  (l) => ActionChip(
                    avatar: Icon(
                      l.name == 'chainsaw'
                          ? Icons.warning_amber_outlined
                          : Icons.forest_outlined,
                      size: 16,
                    ),
                    label: Text(l.displayName),
                    onPressed: () => onSelect(l.name),
                  ),
                ),
                ActionChip(
                  avatar: const Icon(Icons.close, size: 16),
                  label: const Text('Cancel'),
                  onPressed: onCancel,
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _OverrideSheet extends StatelessWidget {
  final List<AppLabel> labels;
  final void Function(String) onSelect;

  const _OverrideSheet({required this.labels, required this.onSelect});

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
            Text('Override label to…', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'This directly updates the training pool label. No consensus needed.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import '../../../core/api/providers.dart';
import '../../../core/models/models.dart';
import '../../../core/widgets/account_menu_button.dart';
import '../../../app/theme.dart';

class ConsensusScreen extends ConsumerStatefulWidget {
  const ConsensusScreen({super.key});

  @override
  ConsumerState<ConsensusScreen> createState() => _ConsensusScreenState();
}

class _ConsensusScreenState extends ConsumerState<ConsensusScreen> {
  final _player = AudioPlayer();
  String? _playingId;
  final Set<String> _processing = {};
  final Set<String> _voted = {};

  @override
  void initState() {
    super.initState();
    // Refetch on every visit to this tab, since it's a normal route
    // (not a kept-alive IndexedStack tab) — this is our "on focus" refresh.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(consensusOpenProvider);
    });
  }

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
      await _player.playerStateStream.firstWhere(
        (s) => s.processingState == ProcessingState.completed,
      );
    } catch (e) {
      _snack('Playback error: $e');
    } finally {
      if (mounted) setState(() => _playingId = null);
    }
  }

  Future<void> _castVote(String segmentId, String verdict) async {
    setState(() => _processing.add(segmentId));
    try {
      final result =
          await ref.read(consensusServiceProvider).castVote(segmentId, verdict);
      setState(() => _voted.add(segmentId));
      ref.invalidate(consensusOpenProvider);
      if (result['consensus_reached'] == true) {
        final label = result['final_label'] as String?;
        _snack(
          label != null
              ? 'Consensus reached — label set to "$label"'
              : 'Consensus reached',
        );
      }
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _processing.remove(segmentId));
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final segmentsAsync = ref.watch(consensusOpenProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Consensus'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(consensusOpenProvider),
          ),
          const SizedBox(width: 4),
          const AccountMenuButton(),
          const SizedBox(width: 8),
        ],
      ),
      body: segmentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (segments) {
          if (segments.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.how_to_vote_outlined,
                    size: 64,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text('No open disputes', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    'When a segment is reported, it appears here for voting.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              Container(
                width: double.infinity,
                color: theme.colorScheme.surfaceContainerHigh,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Text(
                  '${segments.length} open dispute${segments.length == 1 ? '' : 's'}. '
                  '"Agree" = accept the proposed label. "Disagree" = keep the current one.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: segments.length,
                  itemBuilder: (_, i) => _ConsensusCard(
                    segment: segments[i],
                    isPlaying: _playingId == segments[i].id,
                    isProcessing: _processing.contains(segments[i].id),
                    hasVoted: segments[i].userVoted ||
                        _voted.contains(segments[i].id),
                    onPlay: () => _togglePlay(segments[i].id),
                    onAgree: () => _castVote(segments[i].id, 'agree'),
                    onDisagree: () => _castVote(segments[i].id, 'disagree'),
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

class _ConsensusCard extends StatelessWidget {
  final Segment segment;
  final bool isPlaying;
  final bool isProcessing;
  final bool hasVoted;
  final VoidCallback onPlay;
  final VoidCallback onAgree;
  final VoidCallback onDisagree;

  const _ConsensusCard({
    required this.segment,
    required this.isPlaying,
    required this.isProcessing,
    required this.hasVoted,
    required this.onPlay,
    required this.onAgree,
    required this.onDisagree,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = segment.effectiveLabel ?? 'unknown';
    final isChainsaw = label == 'chainsaw';
    const required = 3;
    final agreeN = segment.agreeCount;
    final disagreeN = segment.disagreeCount;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Audio + time
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
              ],
            ),
            const SizedBox(height: 10),

            // Current label
            Row(
              children: [
                Text(
                  'Current label: ',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
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
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Proposed label — what's actually being voted on
            Row(
              children: [
                Text(
                  'Proposed: ',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.swap_horiz_rounded,
                        size: 14,
                        color: theme.colorScheme.onTertiaryContainer,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        segment.proposedLabel ?? '—',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onTertiaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Vote tallies
            Row(
              children: [
                _VotePill(
                  icon: Icons.thumb_up_outlined,
                  count: agreeN,
                  color: AppColors.canopy,
                  label: 'Agree',
                ),
                const SizedBox(width: 12),
                _VotePill(
                  icon: Icons.thumb_down_outlined,
                  count: disagreeN,
                  color: theme.colorScheme.error,
                  label: 'Disagree',
                ),
                const Spacer(),
                Text(
                  '$required needed',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Progress bar — whichever side is leading
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: agreeN >= disagreeN
                    ? agreeN / required
                    : disagreeN / required,
                minHeight: 5,
                color: agreeN >= disagreeN
                    ? AppColors.canopy
                    : theme.colorScheme.error,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 14),

            if (isProcessing)
              const Center(child: CircularProgressIndicator())
            else if (hasVoted)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 16,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'You voted on this segment',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                        side: BorderSide(color: theme.colorScheme.error),
                      ),
                      onPressed: onDisagree,
                      icon: const Icon(Icons.thumb_down_outlined, size: 18),
                      label: const Text('Disagree'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.canopy,
                      ),
                      onPressed: onAgree,
                      icon: const Icon(Icons.thumb_up_outlined, size: 18),
                      label: const Text('Agree'),
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

class _VotePill extends StatelessWidget {
  final IconData icon;
  final int count;
  final Color color;
  final String label;

  const _VotePill({
    required this.icon,
    required this.count,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          '$count $label',
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

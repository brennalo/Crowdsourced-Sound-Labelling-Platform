import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/providers.dart';
import '../../../core/models/models.dart';
import '../../../app/theme.dart';
import 'package:url_launcher/url_launcher.dart';

class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen>
    with SingleTickerProviderStateMixin {
  bool _requesting = false;
  bool _retraining = false;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _requestExport() async {
    setState(() => _requesting = true);
    try {
      await ref.read(exportServiceProvider).requestExport();
      ref.invalidate(myExportsProvider);
      _snack('Export queued — check below when ready.');
    } catch (e) {
      _snack('Failed: $e');
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  Future<void> _triggerRetrain() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Trigger Retraining?'),
        content: const Text(
            'This will queue a full model retrain using all training pool data '
            'plus the frugalai base dataset. It may take a few minutes.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Retrain')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _retraining = true);
    try {
      await ref.read(researcherServiceProvider).triggerRetrain();
      _snack('Retrain job queued.');
    } catch (e) {
      _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _retraining = false);
    }
  }

  Future<void> _openDownload(String jobId) async {
    try {
      final url = await ref.read(exportServiceProvider).getDownloadUrl(jobId);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      _snack('Error: $e');
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statsAsync = ref.watch(exportStatsProvider);
    final exportsAsync = ref.watch(myExportsProvider);
    final retrainingAsync = ref.watch(retrainingJobsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Export'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(exportStatsProvider);
              ref.invalidate(myExportsProvider);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Stats panel ───────────────────────────────────
          statsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Stats error: $e'),
            data: (stats) => _StatsPanel(stats: stats),
          ),
          const SizedBox(height: 20),

          // ── Action buttons ────────────────────────────────
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _requesting ? null : _requestExport,
                  icon: _requesting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.download_outlined),
                  label: const Text('Export Dataset'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _retraining ? null : _triggerRetrain,
                  icon: _retraining
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.model_training_outlined),
                  label: const Text('Retrain Model'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── History tabs ──────────────────────────────────
          TabBar(
            controller: _tabController,
            labelColor: theme.colorScheme.primary,
            unselectedLabelColor: theme.colorScheme.outline,
            tabs: const [
              Tab(text: 'Exports'),
              Tab(text: 'Retraining'),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            // TabBarView needs a bounded height since it's inside a ListView.
            // Adjust this value if content is taller than expected on your screens.
            height: 400,
            child: TabBarView(
              controller: _tabController,
              children: [
                // ── Past exports ──────────────────────────
                exportsAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text('Error: $e'),
                  data: (exports) {
                    if (exports.isEmpty) {
                      return RefreshIndicator(
                        onRefresh: () async =>
                            ref.invalidate(myExportsProvider),
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: 200,
                              child: Center(
                                child: Text('No exports yet.',
                                    style: TextStyle(
                                        color: theme.colorScheme.outline)),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return RefreshIndicator(
                      onRefresh: () async => ref.invalidate(myExportsProvider),
                      child: ListView(
                        children: exports
                            .map((j) => _ExportJobTile(
                                  job: j,
                                  onDownload: () => _openDownload(j.id),
                                ))
                            .toList(),
                      ),
                    );
                  },
                ),

                // ── Retraining history ────────────────────
                retrainingAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text('Error: $e'),
                  data: (jobs) {
                    if (jobs.isEmpty) {
                      return RefreshIndicator(
                        onRefresh: () async =>
                            ref.invalidate(retrainingJobsProvider),
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: 200,
                              child: Center(
                                child: Text('No retraining jobs yet.',
                                    style: TextStyle(
                                        color: theme.colorScheme.outline)),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return RefreshIndicator(
                      onRefresh: () async =>
                          ref.invalidate(retrainingJobsProvider),
                      child: ListView(
                        children: jobs
                            .map((j) => _RetrainingJobTile(job: j))
                            .toList(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsPanel extends StatelessWidget {
  final ExportStats stats;
  const _StatsPanel({required this.stats});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Training Pool', style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),
          _StatRow(label: 'Total segments', value: '${stats.totalInPool}'),
          _StatRow(
              label: 'Added last 7 days', value: '+${stats.addedLast7Days}'),
          _StatRow(label: 'Consensus flips', value: '${stats.consensusFlips}'),
          _StatRow(
              label: 'Researcher corrections',
              value: '${stats.researcherCorrections}'),
          const SizedBox(height: 12),
          Text('Label distribution', style: theme.textTheme.labelMedium),
          const SizedBox(height: 8),
          ...stats.labelDistribution.entries.map((e) => _LabelBar(
                label: e.key,
                count: e.value,
                total: stats.totalInPool,
              )),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  const _StatRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          const Spacer(),
          Text(value,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _LabelBar extends StatelessWidget {
  final String label;
  final int count;
  final int total;
  const _LabelBar(
      {required this.label, required this.count, required this.total});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = total > 0 ? count / total : 0.0;
    final isChainsaw = label == 'chainsaw';
    final color =
        isChainsaw ? theme.colorScheme.error : theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 8,
                color: color,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('$count', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _ExportJobTile extends StatelessWidget {
  final ExportJob job;
  final VoidCallback onDownload;
  const _ExportJobTile({required this.job, required this.onDownload});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color, text) = switch (job.status) {
      'done' => (Icons.check_circle_outline, AppColors.canopy, 'Ready'),
      'failed' => (Icons.error_outline, theme.colorScheme.error, 'Failed'),
      _ => (Icons.hourglass_empty, theme.colorScheme.outline, 'Processing…'),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(text,
            style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        subtitle: Text(_fmt(job.requestedAt),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline)),
        trailing: job.isDone
            ? IconButton(
                icon: const Icon(Icons.download), onPressed: onDownload)
            : null,
      ),
    );
  }

  String _fmt(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

class _RetrainingJobTile extends StatelessWidget {
  final RetrainingJob job;
  const _RetrainingJobTile({required this.job});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color, text) = switch (job.status) {
      'done' => (Icons.check_circle_outline, AppColors.canopy, 'Done'),
      'failed' => (Icons.error_outline, theme.colorScheme.error, 'Failed'),
      'running' => (Icons.autorenew, theme.colorScheme.primary, 'Running…'),
      _ => (Icons.hourglass_empty, theme.colorScheme.outline, 'Queued'),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(text,
            style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${job.triggeredBy} · ${_fmt(job.triggeredAt)}'
          '${job.errorLog != null ? '\n${job.errorLog}' : ''}',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
        isThreeLine: job.errorLog != null,
      ),
    );
  }

  String _fmt(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

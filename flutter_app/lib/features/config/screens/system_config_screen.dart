//Programmer Name - Brenna Lo
//Program Name : system_config_screen.dart
// Description : Central "Configuration" screen for researchers/admins — everything a researcher tunes about how the pipeline behaves lives here
// First Written on : 2024-06-10
// Edited on : 2024-07-18

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../../core/api/providers.dart';
import '../../../core/models/models.dart';
import '../../../core/widgets/account_menu_button.dart';

class ConfigurationScreen extends StatelessWidget {
  const ConfigurationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Configuration'),
          actions: const [
            AccountMenuButton(),
            SizedBox(width: 8),
          ],
          bottom: const TabBar(tabs: [
            Tab(text: 'Labels'),
            Tab(text: 'Thresholds'),
          ]),
        ),
        body: const TabBarView(children: [
          _LabelsTab(),
          _ThresholdsTab(),
        ]),
      ),
    );
  }
}

// ── Labels tab ───────────────────────────────────────────────────

class _LabelsTab extends ConsumerStatefulWidget {
  const _LabelsTab();

  @override
  ConsumerState<_LabelsTab> createState() => _LabelsTabState();
}

class _LabelsTabState extends ConsumerState<_LabelsTab> {
  final _nameController = TextEditingController();
  final _displayNameController = TextEditingController();
  bool _saving = false;
  final Set<String> _toggling = {};

  @override
  void dispose() {
    _nameController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _addLabel() async {
    final name = _nameController.text.trim();
    final displayName = _displayNameController.text.trim();
    if (name.isEmpty || displayName.isEmpty) {
      _snack('Name and display name are both required.');
      return;
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(labelServiceProvider)
          .createLabel(name: name, displayName: displayName);
      _nameController.clear();
      _displayNameController.clear();
      ref.invalidate(allLabelsProvider);
      ref.invalidate(labelsProvider);
      _snack('Label added.');
    } on DioException catch (e) {
      _snack(e.response?.data?['detail']?.toString() ?? 'Failed to add label');
    } catch (e) {
      _snack('Failed to add label: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleLabel(AppLabel label, bool newValue) async {
    setState(() => _toggling.add(label.id));
    try {
      await ref.read(labelServiceProvider).setLabelActive(label.id, newValue);
      ref.invalidate(allLabelsProvider);
      ref.invalidate(labelsProvider);
    } catch (e) {
      _snack('Failed to update label: $e');
    } finally {
      if (mounted) setState(() => _toggling.remove(label.id));
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelsAsync = ref.watch(allLabelsProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add Label', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name (internal, e.g. "generator")',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _displayNameController,
                decoration: const InputDecoration(
                  labelText: 'Display name (e.g. "Generator Noise")',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _addLabel,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text('All Labels', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        labelsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text('Error loading labels: $e'),
          data: (labels) {
            if (labels.isEmpty) {
              return Text('No labels yet.',
                  style: TextStyle(color: theme.colorScheme.outline));
            }
            return Column(
              children: labels
                  .map((l) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: SwitchListTile(
                          title: Text(l.displayName),
                          subtitle: Text(
                            l.name,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.outline),
                          ),
                          value: l.isActive,
                          onChanged: _toggling.contains(l.id)
                              ? null
                              : (v) => _toggleLabel(l, v),
                        ),
                      ))
                  .toList(),
            );
          },
        ),
      ],
    );
  }
}

// ── Thresholds tab ───────────────────────────────────────────────

class _ThresholdsTab extends ConsumerStatefulWidget {
  const _ThresholdsTab();

  @override
  ConsumerState<_ThresholdsTab> createState() => _ThresholdsTabState();
}

class _ThresholdsTabState extends ConsumerState<_ThresholdsTab> {
  double? _silence;
  double? _confidence;
  int? _rejection;
  bool _saving = false;
  bool _dirty = false;

  void _seedFrom(SystemConfig config) {
    _silence ??= config.silenceThresholdDbfs;
    _confidence ??= config.confidenceThreshold;
    _rejection ??= config.rejectionThreshold;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(configServiceProvider).updateConfig(
            silenceThresholdDbfs: _silence,
            confidenceThreshold: _confidence,
            rejectionThreshold: _rejection,
          );
      ref.invalidate(systemConfigProvider);
      setState(() => _dirty = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thresholds updated.')),
        );
      }
    } on DioException catch (e) {
      _snack(e.response?.data?['detail']?.toString() ?? 'Failed to save');
    } catch (e) {
      _snack('Failed to save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final configAsync = ref.watch(systemConfigProvider);

    return configAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Failed to load: $e')),
      data: (config) {
        _seedFrom(config);
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Changes apply to the next task run — segmentation, '
              'suggestion routing, and rejection counting. They don\'t '
              'retroactively affect segments already processed.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 24),
            _ThresholdTile(
              title: 'Silence threshold',
              subtitle:
                  'Segments quieter than this (dBFS RMS) are dropped as silent.',
              value: _silence!,
              min: -80,
              max: -10,
              divisions: 70,
              valueLabel: '${_silence!.toStringAsFixed(0)} dBFS',
              onChanged: (v) => setState(() {
                _silence = v;
                _dirty = true;
              }),
            ),
            const Divider(height: 40),
            _ThresholdTile(
              title: 'Suggestion confidence threshold',
              subtitle:
                  'Predictions at or above this confidence go to suggestion review; '
                  'below it, contributors pick the label manually.',
              value: _confidence!,
              min: 0.5,
              max: 0.99,
              divisions: 49,
              valueLabel: '${(_confidence! * 100).toStringAsFixed(0)}%',
              onChanged: (v) => setState(() {
                _confidence = v;
                _dirty = true;
              }),
            ),
            const Divider(height: 40),
            _ThresholdTile(
              title: 'Retrain trigger (rejections)',
              subtitle:
                  'Number of suggestion rejections since the last retrain that '
                  'triggers a new Cloud Run retraining job.',
              value: _rejection!.toDouble(),
              min: 20,
              max: 500,
              divisions: 48,
              valueLabel: '${_rejection!}',
              onChanged: (v) => setState(() {
                _rejection = v.round();
                _dirty = true;
              }),
            ),
            const SizedBox(height: 8),
            Text(
              'Last updated ${config.updatedAt.toLocal()}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: (_dirty && !_saving) ? _save : null,
              child: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save changes'),
            ),
          ],
        );
      },
    );
  }
}

class _ThresholdTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String valueLabel;
  final ValueChanged<double> onChanged;

  const _ThresholdTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Text(valueLabel,
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.primary)),
          ],
        ),
        const SizedBox(height: 4),
        Text(subtitle,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.outline)),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: valueLabel,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

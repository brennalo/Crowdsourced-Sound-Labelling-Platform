import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../../core/api/providers.dart';
import '../../../core/models/models.dart';

class LabelsScreen extends ConsumerStatefulWidget {
  const LabelsScreen({super.key});

  @override
  ConsumerState<LabelsScreen> createState() => _LabelsScreenState();
}

class _LabelsScreenState extends ConsumerState<LabelsScreen> {
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Labels'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(allLabelsProvider),
          ),
        ],
      ),
      body: ListView(
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
      ),
    );
  }
}

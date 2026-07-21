//Programmer Name - Brenna Lo
//Program Name : admin_screen.dart
// Description : Admin screen for managing users and segments
// First Written on : 2024-06-10
// Edited on : 2024-07-18

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../../core/api/providers.dart';
import '../../../core/models/models.dart';
import '../../../core/widgets/account_menu_button.dart';

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Manage Users'),
          actions: const [
            AccountMenuButton(),
            SizedBox(width: 8),
          ],
          bottom: const TabBar(tabs: [
            Tab(text: 'Contributors'),
            Tab(text: 'Researchers'),
            Tab(text: 'Segments'),
          ]),
        ),
        body: const TabBarView(children: [
          _UsersTab(role: 'contributor'),
          _UsersTab(role: 'researcher'),
          _SegmentsTab(),
        ]),
      ),
    );
  }
}

class _UsersTab extends ConsumerWidget {
  final String role;
  const _UsersTab({required this.role});

  Future<void> _confirmDeactivate(
      BuildContext context, WidgetRef ref, AdminUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Deactivate account?'),
        content: Text(
          '${user.name} won\'t be able to log in anymore. Their recordings, '
          'segments, and annotations are kept as-is and stay in the pool. '
          'This can be undone later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(adminServiceProvider).deactivateUser(user.id);
      ref.invalidate(adminUsersProvider(role));
    } on DioException catch (e) {
      _snack(context, e.response?.data?['detail']?.toString() ?? 'Failed');
    }
  }

  Future<void> _reactivate(
      BuildContext context, WidgetRef ref, AdminUser user) async {
    try {
      await ref.read(adminServiceProvider).reactivateUser(user.id);
      ref.invalidate(adminUsersProvider(role));
    } on DioException catch (e) {
      _snack(context, e.response?.data?['detail']?.toString() ?? 'Failed');
    }
  }

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(adminUsersProvider(role));
    final outline = Theme.of(context).colorScheme.outline;

    return usersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Failed to load: $e')),
      data: (users) {
        if (users.isEmpty) {
          return Center(
              child:
                  Text('No ${role}s yet.', style: TextStyle(color: outline)));
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(adminUsersProvider(role)),
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: users.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (_, i) {
              final u = users[i];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child:
                        Text(u.name.isNotEmpty ? u.name[0].toUpperCase() : '?'),
                  ),
                  title: Row(children: [
                    Flexible(
                        child: Text(u.name, overflow: TextOverflow.ellipsis)),
                    if (!u.isActive) ...[
                      const SizedBox(width: 8),
                      Chip(
                        label: const Text('Deactivated',
                            style: TextStyle(fontSize: 11)),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ],
                  ]),
                  subtitle: Text(
                    '${u.email}\n${u.recordingsCount} recordings · ${u.segmentsCount} segments',
                    style: TextStyle(color: outline),
                  ),
                  isThreeLine: true,
                  trailing: u.isActive
                      ? IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Deactivate',
                          onPressed: () => _confirmDeactivate(context, ref, u),
                        )
                      : IconButton(
                          icon: const Icon(Icons.restore_rounded),
                          tooltip: 'Reactivate',
                          onPressed: () => _reactivate(context, ref, u),
                        ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _SegmentsTab extends ConsumerWidget {
  const _SegmentsTab();

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, AdminSegment segment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete segment?'),
        content: const Text(
          'This permanently removes the segment and its consensus votes / '
          'label history. This can\'t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(adminServiceProvider).deleteSegment(segment.id);
      ref.invalidate(adminSegmentsProvider);
    } on DioException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.response?.data?['detail']?.toString() ?? 'Failed')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final segmentsAsync = ref.watch(adminSegmentsProvider);
    final outline = Theme.of(context).colorScheme.outline;

    return segmentsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Failed to load: $e')),
      data: (segments) {
        if (segments.isEmpty) {
          return Center(
              child: Text('No segments.', style: TextStyle(color: outline)));
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(adminSegmentsProvider),
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: segments.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (_, i) {
              final s = segments[i];
              return Card(
                child: ListTile(
                  title: Text(
                    s.sequenceNum != null
                        ? 'Segment ${s.sequenceNum} · ${s.uploaderName}'
                        : s.uploaderName,
                  ),
                  subtitle: Text(
                    '${s.reviewStatus}'
                    '${s.effectiveLabel != null ? ' · ${s.effectiveLabel}' : ''}',
                    style: TextStyle(color: outline),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Delete',
                    onPressed: () => _confirmDelete(context, ref, s),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

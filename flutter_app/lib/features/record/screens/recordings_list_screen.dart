//Programmer Name : Brenna Lo
//Program Name : recordings_list_screen.dart
//Description : UI and stateful widget of recordings list screen for contributor
//First Written on : 2024-06-10
//Edited on : 2024-07-18

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '/core/api/providers.dart';
import '/core/models/models.dart';
import '/core/widgets/account_menu_button.dart';
import '/app/theme.dart';

class RecordingsListScreen extends ConsumerWidget {
  const RecordingsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordingsAsync = ref.watch(myRecordingsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Recordings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(myRecordingsProvider),
          ),
          const SizedBox(width: 4),
          const AccountMenuButton(),
          const SizedBox(width: 8),
        ],
      ),
      body: recordingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (recordings) {
          if (recordings.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.mic_none,
                      size: 64, color: theme.colorScheme.outline),
                  const SizedBox(height: 16),
                  Text('No recordings yet', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('Go to Record to contribute audio',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.outline)),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(myRecordingsProvider),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: recordings.length,
              itemBuilder: (context, i) =>
                  _RecordingCard(recording: recordings[i]),
            ),
          );
        },
      ),
    );
  }
}

class _RecordingCard extends StatelessWidget {
  final Recording recording;
  const _RecordingCard({required this.recording});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateStr = recording.recordedAt != null
        ? DateFormat('d MMM yyyy, HH:mm')
            .format(recording.recordedAt!.toLocal())
        : 'Unknown date';

    Color statusColor;
    IconData statusIcon;
    switch (recording.status) {
      case 'done':
        statusColor = AppColors.canopy;
        statusIcon = Icons.check_circle_outline;
        break;
      case 'processing':
        statusColor = AppColors.amber;
        statusIcon = Icons.hourglass_top_outlined;
        break;
      default:
        statusColor = theme.colorScheme.error;
        statusIcon = Icons.error_outline;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child:
              Icon(Icons.audio_file_outlined, color: theme.colorScheme.primary),
        ),
        title: Text(dateStr, style: theme.textTheme.bodyLarge),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (recording.durationSec != null)
              Text('${recording.durationSec!.toStringAsFixed(1)}s'),
            Row(
              children: [
                Icon(statusIcon, size: 14, color: statusColor),
                const SizedBox(width: 4),
                Text(recording.status,
                    style: TextStyle(color: statusColor, fontSize: 12)),
              ],
            ),
          ],
        ),
        trailing: recording.isDone
            ? IconButton(
                icon: const Icon(Icons.label_outline),
                tooltip: 'Annotate segments',
                onPressed: () =>
                    context.go('/recordings/${recording.id}/annotate'),
              )
            : null,
      ),
    );
  }
}

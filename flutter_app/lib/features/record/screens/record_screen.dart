import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import '/core/api/providers.dart';
import '/app/theme.dart';
import '../widgets/forest_hero.dart';

class RecordScreen extends ConsumerStatefulWidget {
  const RecordScreen({super.key});

  @override
  ConsumerState<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends ConsumerState<RecordScreen> {
  final _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _isUploading = false;
  String? _recordedPath;
  Duration _elapsed = Duration.zero;
  Timer? _timer;
  String? _statusMessage;
  bool _statusIsError = false;

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      _showStatus('Microphone permission denied', isError: true);
      return;
    }

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.wav';

    await _recorder.start(
      const RecordConfig(
          encoder: AudioEncoder.wav, sampleRate: 22050, numChannels: 1),
      path: path,
    );

    setState(() {
      _isRecording = true;
      _elapsed = Duration.zero;
      _recordedPath = null;
      _statusMessage = null;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    final path = await _recorder.stop();
    setState(() {
      _isRecording = false;
      _recordedPath = path;
    });
    if (path != null) _showStatus('Recording saved. Tap upload to submit.');
  }

  Future<void> _uploadRecording() async {
    if (_recordedPath == null) return;
    setState(() {
      _isUploading = true;
      _statusMessage = null;
    });

    try {
      await ref.read(recordingServiceProvider).uploadRecording(
            audioFile: File(_recordedPath!),
            recordedAt: DateTime.now(),
          );
      // Invalidate recordings + segments so the forest grows immediately
      ref.invalidate(myRecordingsProvider);
      ref.invalidate(allMySegmentsProvider);
      _showStatus('Uploaded! Your forest just grew a little.');
      setState(() {
        _recordedPath = null;
      });
    } catch (e) {
      _showStatus('Upload failed: $e', isError: true);
    } finally {
      setState(() => _isUploading = false);
    }
  }

  void _showStatus(String msg, {bool isError = false}) {
    setState(() {
      _statusMessage = msg;
      _statusIsError = isError;
    });
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recordingsAsync = ref.watch(myRecordingsProvider);
    final segmentsAsync = ref.watch(allMySegmentsProvider);

    final recordingsCount = recordingsAsync.asData?.value.length ?? 0;
    final segmentsInPool =
        segmentsAsync.asData?.value.where((s) => s.isInPool).length ?? 0;
    final completedTrees = recordingsCount ~/ ForestHero.treeThreshold;
    final currentStage =
        ForestStage.forCount(recordingsCount % ForestHero.treeThreshold);

    return Scaffold(
      appBar: AppBar(title: const Text('Your Forest')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          // ── Growing forest hero ─────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              children: [
                ForestHero(recordingsCount: recordingsCount),
                const SizedBox(height: 4),
                Text(
                  completedTrees > 0
                      ? '${currentStage.label} · $completedTrees tree${completedTrees == 1 ? '' : 's'} grown'
                      : currentStage.label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Your forest stats ────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.mic_rounded,
                  label: 'Recordings',
                  value: '$recordingsCount',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  icon: Icons.park_rounded,
                  label: 'In training pool',
                  value: '$segmentsInPool',
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // ── Elapsed timer ────────────────────────────────────
          Text(
            _formatDuration(_elapsed),
            textAlign: TextAlign.center,
            style: theme.textTheme.displayMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: _isRecording
                  ? theme.colorScheme.error
                  : theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _isRecording
                ? 'Recording...'
                : (_recordedPath != null
                    ? 'Ready to upload'
                    : 'Tap to plant a new recording'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge
                ?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 32),

          // ── Record button ────────────────────────────────────
          Center(
            child: GestureDetector(
              onTap: _isUploading
                  ? null
                  : (_isRecording ? _stopRecording : _startRecording),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 104,
                height: 104,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isRecording
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                  boxShadow: [
                    BoxShadow(
                        color: (_isRecording
                                ? theme.colorScheme.error
                                : theme.colorScheme.primary)
                            .withOpacity(0.35),
                        blurRadius: 28,
                        spreadRadius: 2,
                        offset: const Offset(0, 8)),
                  ],
                ),
                child: Icon(
                  _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                  color: Colors.white,
                  size: 48,
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),

          // ── Upload button ────────────────────────────────────
          if (_recordedPath != null && !_isRecording)
            FilledButton.icon(
              onPressed: _isUploading ? null : _uploadRecording,
              icon: _isUploading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.upload_rounded),
              label: Text(_isUploading ? 'Uploading...' : 'Upload Recording'),
            ),

          if (_statusMessage != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: (_statusIsError
                    ? theme.colorScheme.errorContainer
                    : theme.colorScheme.primaryContainer),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _statusMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _statusIsError
                      ? theme.colorScheme.onErrorContainer
                      : theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ],

          const SizedBox(height: 28),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  label,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/api/providers.dart';

class ShellScreen extends ConsumerWidget {
  final Widget child;
  const ShellScreen({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isResearcher = ref.watch(authProvider).isResearcher;
    final location = GoRouterState.of(context).matchedLocation;

    return isResearcher
        ? _ResearcherShell(child: child, location: location)
        : _ContributorShell(child: child, location: location);
  }
}

// ── Shared logout dialog ──────────────────────────────────────

Future<void> showLogoutDialog(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Log Out'),
      content: const Text('Are you sure you want to log out?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Log Out'),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await ref.read(authProvider.notifier).logout();
    if (context.mounted) context.go('/login');
  }
}

// ── Contributor: Record | My Clips | Consensus | Pool ─────────

class _ContributorShell extends ConsumerWidget {
  final Widget child;
  final String location;
  const _ContributorShell({required this.child, required this.location});

  int _idx(String loc) {
    if (loc.startsWith('/record') || loc.startsWith('/recordings')) return 0;
    if (loc.startsWith('/my-clips')) return 1;
    if (loc.startsWith('/consensus')) return 2;
    if (loc.startsWith('/pool')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;

    return Scaffold(
      appBar: AppBar(
        title: Text(_titleFor(location)),
        actions: [
          PopupMenuButton<String>(
            icon: CircleAvatar(
              radius: 16,
              child: Text(
                (user?.name ?? '?')[0].toUpperCase(),
                style: const TextStyle(fontSize: 14),
              ),
            ),
            onSelected: (value) {
              if (value == 'logout') showLogoutDialog(context, ref);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user?.name ?? '',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(user?.email ?? '',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey)),
                    Text('Contributor',
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 18),
                    SizedBox(width: 10),
                    Text('Log Out'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _idx(location),
        onDestinationSelected: (i) {
          switch (i) {
            case 0:
              context.go('/record');
              break;
            case 1:
              context.go('/my-clips');
              break;
            case 2:
              context.go('/consensus');
              break;
            case 3:
              context.go('/pool');
              break;
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.mic_outlined),
            selectedIcon: Icon(Icons.mic),
            label: 'Record',
          ),
          NavigationDestination(
            icon: Icon(Icons.audio_file_outlined),
            selectedIcon: Icon(Icons.audio_file),
            label: 'My Clips',
          ),
          NavigationDestination(
            icon: Icon(Icons.how_to_vote_outlined),
            selectedIcon: Icon(Icons.how_to_vote),
            label: 'Consensus',
          ),
          NavigationDestination(
            icon: Icon(Icons.dataset_outlined),
            selectedIcon: Icon(Icons.dataset),
            label: 'Pool',
          ),
        ],
      ),
    );
  }

  String _titleFor(String loc) {
    if (loc.startsWith('/record')) return 'Record';
    if (loc.startsWith('/my-clips')) return 'My Clips';
    if (loc.startsWith('/consensus')) return 'Consensus';
    if (loc.startsWith('/pool')) return 'Training Pool';
    return 'Forest Sound';
  }
}

// ── Researcher: Review | Pool | Export ────────────────────────

class _ResearcherShell extends ConsumerWidget {
  final Widget child;
  final String location;
  const _ResearcherShell({required this.child, required this.location});

  int _idx(String loc) {
    if (loc.startsWith('/review')) return 0;
    if (loc.startsWith('/pool')) return 1;
    if (loc.startsWith('/export')) return 2;
    if (loc.startsWith('/labels')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;

    return Scaffold(
      appBar: AppBar(
        title: Text(_titleFor(location)),
        actions: [
          PopupMenuButton<String>(
            icon: CircleAvatar(
              radius: 16,
              child: Text(
                (user?.name ?? '?')[0].toUpperCase(),
                style: const TextStyle(fontSize: 14),
              ),
            ),
            onSelected: (value) {
              if (value == 'logout') showLogoutDialog(context, ref);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user?.name ?? '',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(user?.email ?? '',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey)),
                    Text('Researcher',
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 18),
                    SizedBox(width: 10),
                    Text('Log Out'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _idx(location),
        onDestinationSelected: (i) {
          switch (i) {
            case 0:
              context.go('/review');
              break;
            case 1:
              context.go('/pool');
              break;
            case 2:
              context.go('/export');
              break;
            case 3:
              context.go('/labels');
              break;
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.fact_check_outlined),
            selectedIcon: Icon(Icons.fact_check),
            label: 'Review',
          ),
          NavigationDestination(
            icon: Icon(Icons.dataset_outlined),
            selectedIcon: Icon(Icons.dataset),
            label: 'Pool',
          ),
          NavigationDestination(
            icon: Icon(Icons.download_outlined),
            selectedIcon: Icon(Icons.download),
            label: 'Export',
          ),
          NavigationDestination(
            icon: Icon(Icons.sell_outlined),
            selectedIcon: Icon(Icons.sell),
            label: 'Labels',
          ),
        ],
      ),
    );
  }

  String _titleFor(String loc) {
    if (loc.startsWith('/review')) return 'Review';
    if (loc.startsWith('/pool')) return 'Training Pool';
    if (loc.startsWith('/export')) return 'Export';
    if (loc.startsWith('/labels')) return 'Manage Labels';
    return 'Forest Sound';
  }
}

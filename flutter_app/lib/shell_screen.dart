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

// ── Contributor: Record | My Clips | Consensus | Pool ─────────

class _ContributorShell extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _idx(location),
        onDestinationSelected: (i) {
          switch (i) {
            case 0: context.go('/record'); break;
            case 1: context.go('/my-clips'); break;
            case 2: context.go('/consensus'); break;
            case 3: context.go('/pool'); break;
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.mic_outlined), selectedIcon: Icon(Icons.mic), label: 'Record'),
          NavigationDestination(
            icon: Icon(Icons.audio_file_outlined), selectedIcon: Icon(Icons.audio_file), label: 'My Clips'),
          NavigationDestination(
            icon: Icon(Icons.how_to_vote_outlined), selectedIcon: Icon(Icons.how_to_vote), label: 'Consensus'),
          NavigationDestination(
            icon: Icon(Icons.dataset_outlined), selectedIcon: Icon(Icons.dataset), label: 'Pool'),
        ],
      ),
    );
  }
}

// ── Researcher: Review | Pool | Export ────────────────────────

class _ResearcherShell extends StatelessWidget {
  final Widget child;
  final String location;
  const _ResearcherShell({required this.child, required this.location});

  int _idx(String loc) {
    if (loc.startsWith('/review')) return 0;
    if (loc.startsWith('/pool')) return 1;
    if (loc.startsWith('/export')) return 2;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _idx(location),
        onDestinationSelected: (i) {
          switch (i) {
            case 0: context.go('/review'); break;
            case 1: context.go('/pool'); break;
            case 2: context.go('/export'); break;
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.fact_check_outlined), selectedIcon: Icon(Icons.fact_check), label: 'Review'),
          NavigationDestination(
            icon: Icon(Icons.dataset_outlined), selectedIcon: Icon(Icons.dataset), label: 'Pool'),
          NavigationDestination(
            icon: Icon(Icons.download_outlined), selectedIcon: Icon(Icons.download), label: 'Export'),
        ],
      ),
    );
  }
}

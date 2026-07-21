import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/api/providers.dart';

// Note: this shell used to also render its own AppBar (dynamic title +
// account menu) wrapping every tab's `child`. Since every tab screen
// already renders its own AppBar with the correct title and its own
// screen-specific actions, that produced two stacked app bars with
// duplicate titles. The shell now only owns the bottom nav; the account
// menu moved to `core/widgets/account_menu_button.dart` and is added as a
// trailing action on each screen's own AppBar instead.

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
            selectedIcon: Icon(Icons.mic_rounded),
            label: 'Record',
          ),
          NavigationDestination(
            icon: Icon(Icons.eco_outlined),
            selectedIcon: Icon(Icons.eco_rounded),
            label: 'My Clips',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups_rounded),
            label: 'Consensus',
          ),
          NavigationDestination(
            icon: Icon(Icons.forest_outlined),
            selectedIcon: Icon(Icons.forest_rounded),
            label: 'Pool',
          ),
        ],
      ),
    );
  }
}

// ── Researcher: Review | Pool | Export | Config ────────────────

class _ResearcherShell extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Scaffold(
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
            selectedIcon: Icon(Icons.fact_check_rounded),
            label: 'Review',
          ),
          NavigationDestination(
            icon: Icon(Icons.forest_outlined),
            selectedIcon: Icon(Icons.forest_rounded),
            label: 'Pool',
          ),
          NavigationDestination(
            icon: Icon(Icons.download_outlined),
            selectedIcon: Icon(Icons.download_rounded),
            label: 'Export',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_rounded),
            selectedIcon: Icon(Icons.tune_rounded),
            label: 'Config',
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/api/providers.dart';

class ShellScreen extends ConsumerWidget {
  final Widget child;
  const ShellScreen({super.key, required this.child});

  int _locationToIndex(String location) {
    if (location.startsWith('/record')) return 0;
    if (location.startsWith('/recordings')) return 1;
    if (location.startsWith('/review')) return 2;
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).matchedLocation;
    final currentIndex = _locationToIndex(location);

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (i) {
          switch (i) {
            case 0: context.go('/record'); break;
            case 1: context.go('/recordings'); break;
            case 2: context.go('/review'); break;
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.mic_outlined), selectedIcon: Icon(Icons.mic), label: 'Record'),
          NavigationDestination(icon: Icon(Icons.library_music_outlined), selectedIcon: Icon(Icons.library_music), label: 'My Recordings'),
          NavigationDestination(icon: Icon(Icons.rate_review_outlined), selectedIcon: Icon(Icons.rate_review), label: 'Review'),
        ],
      ),
    );
  }
}

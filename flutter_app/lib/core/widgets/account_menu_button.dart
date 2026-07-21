import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/providers.dart';

/// Confirms and performs logout. Shared by every screen that hosts an
/// [AccountMenuButton] (previously lived only in the shell, back when the
/// shell owned the single app-wide AppBar).
///
/// Deliberately does NOT call `context.go('/login')` itself. The router's
/// `redirect` (see app/router.dart) already sends unauthenticated users to
/// /login automatically once `authProvider` changes — it's wired to a
/// refreshListenable rather than being rebuilt from scratch on every auth
/// change, so it's safe to just let it react. Navigating manually here as
/// well used to race that rebuild and produce a blank white screen.
Future<void> showLogoutDialog(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Log Out'),
      content: const Text('Are you sure you want to log out?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Log Out'),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await ref.read(authProvider.notifier).logout();
  }
}

/// Avatar + dropdown (name, email, role, Log Out).
///
/// Used as a trailing AppBar action on every top-level screen. Each screen
/// keeps its own title and its own screen-specific actions (refresh, sort,
/// etc.) — this widget just adds the one bit of chrome that used to live in
/// a separate wrapping AppBar in the shell, which caused every screen to
/// show two stacked app bars with the same title.
///
/// Admins never see this widget in practice — they're routed straight to
/// and confined to /admin (see router.dart), which has its own copy of this
/// button for logout access, so there's no "Manage Users" entry here to
/// jump between roles. Keeping researcher/contributor chrome and admin
/// chrome fully separate is intentional.
class AccountMenuButton extends ConsumerWidget {
  const AccountMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final user = auth.user;
    final outline = Theme.of(context).colorScheme.outline;
    final roleLabel = user?.isAdmin == true
        ? 'Admin'
        : (auth.isResearcher ? 'Researcher' : 'Contributor');

    return PopupMenuButton<String>(
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
                  style: TextStyle(fontSize: 12, color: outline)),
              Text(roleLabel, style: TextStyle(fontSize: 11, color: outline)),
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
    );
  }
}

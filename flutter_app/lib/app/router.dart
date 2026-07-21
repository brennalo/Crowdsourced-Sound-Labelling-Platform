import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api/providers.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/register_screen.dart';
import '../features/record/screens/record_screen.dart';
import '../features/record/screens/recordings_list_screen.dart';
import '../features/my_clips/screens/my_clips_screen.dart';
import '../features/consensus/screens/consensus_screen.dart';
import '../features/training_pool/screens/training_pool_screen.dart';
import '../features/researcher/screens/researcher_review_screen.dart';
import '../features/export/screens/export_screen.dart';
import '../features/config/screens/system_config_screen.dart';
import '../features/admin/screens/admin_screen.dart';
import '../shell_screen.dart';

/// Bridges Riverpod state changes into go_router's `refreshListenable`.
///
/// IMPORTANT: this is what lets us build the [GoRouter] exactly once. If
/// `routerProvider` below instead did `ref.watch(authProvider)` directly,
/// every auth change (e.g. logout) would tear down and rebuild the entire
/// GoRouter — including the Navigator underneath it — while a manual
/// `context.go(...)` call from the same auth change was still in flight.
/// That race is what produced the blank white screen after logging out:
/// MaterialApp.router briefly had a router config with no valid navigator
/// under it. Notifying listeners instead just re-runs `redirect` on the
/// same, still-alive GoRouter — no teardown, no race.
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    ref.listen(authProvider, (_, __) => notifyListeners());
  }
}

final _authRefreshProvider = Provider<_AuthRefreshNotifier>((ref) {
  final notifier = _AuthRefreshNotifier(ref);
  ref.onDispose(notifier.dispose);
  return notifier;
});

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ref.watch(_authRefreshProvider);

  // Admin is checked before isResearcher: `isResearcher` is true for both
  // researcher AND admin accounts (it gates shared researcher-tier
  // permissions elsewhere in the app), but admins should never actually
  // land in the researcher shell — they get their own dedicated home.
  String initialLocation() {
    final auth = ref.read(authProvider);
    if (!auth.isAuthenticated) return '/login';
    if (auth.user?.isAdmin == true) return '/admin';
    return auth.isResearcher ? '/review' : '/record';
  }

  return GoRouter(
    initialLocation: initialLocation(),
    refreshListenable: refresh,
    redirect: (context, state) {
      // Read fresh auth state on every redirect check, rather than
      // capturing it once when the GoRouter was constructed.
      final auth = ref.read(authProvider);
      final isAuth = auth.isAuthenticated;
      final loc = state.matchedLocation;
      final onAuth = loc == '/login' || loc == '/register';

      if (!isAuth && !onAuth) return '/login';
      if (!isAuth) return null;

      final isAdmin = auth.user?.isAdmin == true;

      if (onAuth) {
        if (isAdmin) return '/admin';
        return auth.isResearcher ? '/review' : '/record';
      }

      // Admins are confined to /admin — keep them out of the
      // researcher/contributor shell entirely rather than mixing roles.
      if (isAdmin && loc != '/admin') return '/admin';

      // Conversely, non-admins shouldn't be able to land on /admin even
      // if they have an old link/bookmark to it.
      if (!isAdmin && loc == '/admin') {
        return auth.isResearcher ? '/review' : '/record';
      }

      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(path: '/admin', builder: (_, __) => const AdminScreen()),
      ShellRoute(
        builder: (context, state, child) => ShellScreen(child: child),
        routes: [
          // ── Contributor routes ─────────────────────────────
          GoRoute(path: '/record', builder: (_, __) => const RecordScreen()),
          GoRoute(
            path: '/recordings',
            builder: (_, __) => const RecordingsListScreen(),
          ),
          GoRoute(path: '/my-clips', builder: (_, __) => const MyClipsScreen()),
          GoRoute(
              path: '/consensus', builder: (_, __) => const ConsensusScreen()),

          // ── Shared ────────────────────────────────────────
          GoRoute(
              path: '/pool', builder: (_, __) => const TrainingPoolScreen()),

          // ── Researcher routes ──────────────────────────────
          GoRoute(
              path: '/review',
              builder: (_, __) => const ResearcherReviewScreen()),
          GoRoute(path: '/export', builder: (_, __) => const ExportScreen()),
          GoRoute(
              path: '/labels', builder: (_, __) => const ConfigurationScreen()),
        ],
      ),
    ],
  );
});

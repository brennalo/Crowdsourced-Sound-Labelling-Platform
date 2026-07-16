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
import '../features/labels/screens/labels_screen.dart';
import '../shell_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authProvider);

  // Router is rebuilt whenever auth state changes, so pick the initial
  // location dynamically from the *current* auth state rather than
  // hardcoding one role's home screen — otherwise a researcher briefly
  // lands on the contributor's /record before manually navigating away.
  String initialLocation() {
    if (!auth.isAuthenticated) return '/login';
    return auth.isResearcher ? '/review' : '/record';
  }

  return GoRouter(
    initialLocation: initialLocation(),
    redirect: (context, state) {
      final isAuth = auth.isAuthenticated;
      final onAuth = state.matchedLocation == '/login' ||
          state.matchedLocation == '/register';
      if (!isAuth && !onAuth) return '/login';
      if (isAuth && onAuth) {
        return auth.isResearcher ? '/review' : '/record';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
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
          GoRoute(path: '/labels', builder: (_, __) => const LabelsScreen()),
        ],
      ),
    ],
  );
});

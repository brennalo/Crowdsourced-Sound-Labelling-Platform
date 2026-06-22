import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api/providers.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/register_screen.dart';
import '../features/record/screens/record_screen.dart';
import '../features/record/screens/recordings_list_screen.dart';
import '../features/annotate/screens/annotate_screen.dart';
import '../features/review/screens/review_screen.dart';
import '../shell_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/record',
    redirect: (context, state) {
      final isAuth = authState.isAuthenticated;
      final onAuthPage = state.matchedLocation == '/login' ||
          state.matchedLocation == '/register';

      if (!isAuth && !onAuthPage) return '/login';
      if (isAuth && onAuthPage) return '/record';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      ShellRoute(
        builder: (context, state, child) => ShellScreen(child: child),
        routes: [
          GoRoute(
            path: '/record',
            builder: (_, __) => const RecordScreen(),
          ),
          GoRoute(
            path: '/recordings',
            builder: (_, __) => const RecordingsListScreen(),
            routes: [
              GoRoute(
                path: ':recordingId/annotate',
                builder: (_, state) => AnnotateScreen(
                  recordingId: state.pathParameters['recordingId']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/review',
            builder: (_, __) => const ReviewScreen(),
          ),
        ],
      ),
    ],
  );
});

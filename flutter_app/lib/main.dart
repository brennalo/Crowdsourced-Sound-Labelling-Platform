import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart'; // generated via `flutterfire configure`
import 'app/router.dart';
import 'app/theme.dart';
import 'core/api/providers.dart';
import 'core/push/push_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Must be registered here, before runApp — this is what lets the OS wake
  // a background isolate to run the handler when the app isn't foregrounded.
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  runApp(const ProviderScope(child: ForestSoundApp()));
}

class ForestSoundApp extends ConsumerWidget {
  const ForestSoundApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    // Kick off permission request + FCM listener setup once per app session.
    ref.watch(pushInitProvider);

    // Register/unregister this device's push token as auth state changes —
    // covers login, logout, and the token being restored from secure
    // storage on a fresh app start.
    ref.listen(authProvider, (previous, next) {
      final push = ref.read(pushServiceProvider);
      final wasAuthed = previous?.isAuthenticated ?? false;
      if (next.isAuthenticated && !wasAuthed) {
        push.registerCurrentToken();
      } else if (!next.isAuthenticated && wasAuthed) {
        push.unregisterCurrentToken();
      }
    });

    return MaterialApp.router(
      title: 'Forest Sound Platform',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: router,
    );
  }
}

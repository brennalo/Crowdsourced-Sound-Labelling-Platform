//Programmer Name - Brenna Lo
//Program Name : push_service.dart
// Description : Push notification service for the Flutter app
// First Written on : 2024-06-10
// Edited on : 2024-07-18

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/providers.dart';

/// Must be a top-level function (not a class method) — this is how the OS
/// invokes it in a separate isolate when a data message arrives while the
/// app is backgrounded/killed. There's no live UI to refresh in that isolate;
/// the foreground listener below (and each screen's own on-open refetch)
/// picks up fresh data the next time the app is actually opened.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

/// Handles FCM setup: permission request, token registration/refresh, and
/// translating an incoming push's `data.type` into a provider invalidation
/// so screens refetch automatically — no polling, no manual pull-to-refresh.
class PushService {
  final Ref ref;
  bool _listenersAttached = false;

  PushService(this.ref);

  Future<void> initialize() async {
    if (_listenersAttached) return;
    _listenersAttached = true;

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    FirebaseMessaging.onMessage.listen(_handleMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);
    messaging.onTokenRefresh.listen((_) => registerCurrentToken());
  }

  Future<void> registerCurrentToken() async {
    if (!ref.read(authProvider).isAuthenticated) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await ref.read(deviceTokenServiceProvider).register(
            token,
            platform:
                defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
          );
    } catch (_) {
      // Best-effort — a missed registration just costs one fewer push,
      // never worth surfacing as an error to the user.
    }
  }

  Future<void> unregisterCurrentToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await ref.read(deviceTokenServiceProvider).unregister(token);
    } catch (_) {
      // Fine to fail silently — worst case a stale token lingers server-side
      // until it naturally errors out and gets pruned there.
    }
  }

  void _handleMessage(RemoteMessage message) {
    switch (message.data['type']) {
      case 'segmentation_done':
        ref.invalidate(myRecordingsProvider);
        ref.invalidate(allMySegmentsProvider);
        ref.invalidate(mySegmentsProvider);
        ref.invalidate(suggestionQueueProvider);
        break;
      case 'export_done':
        ref.invalidate(myExportsProvider);
        break;
      case 'consensus_resolved':
        ref.invalidate(consensusOpenProvider);
        ref.invalidate(trainingPoolProvider);
        break;
      case 'retrain_done':
        ref.invalidate(retrainingJobsProvider);
        break;
      default:
        break;
    }
  }
}

final pushServiceProvider = Provider<PushService>((ref) => PushService(ref));

/// Side-effecting provider — read once from the app root to kick off
/// permission request + listener setup. Deliberately not autoDispose so it
/// only ever runs once per app session.
final pushInitProvider = FutureProvider<void>((ref) async {
  await ref.read(pushServiceProvider).initialize();
});

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

import '../firebase_options.dart';
import '../main.dart';

/// Registers this device for push notifications (plan-sale alerts).
///
/// Delivery works even when the app is closed: FCM 'notification' messages
/// are displayed by the OS itself, so no background handler is needed. The
/// server side is the send-plan-sale-push edge function, which broadcasts to
/// every token stored in the `device_push_tokens` table.
///
/// Everything here is best-effort: if Firebase isn't configured yet
/// (see firebase_options.dart) or the user denies the notification
/// permission, the app simply runs without push.
class PushService {
  PushService._();

  static bool _initialized = false;

  /// Call once at startup (after Supabase.initialize). Safe to call when
  /// Firebase isn't configured — it just no-ops.
  static Future<void> init() async {
    if (_initialized || !DefaultFirebaseOptions.isConfigured) return;
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.android);
      _initialized = true;

      // Android 13+ / iOS require an explicit permission prompt.
      await FirebaseMessaging.instance.requestPermission();

      // Keep the stored token fresh, and re-register it whenever a user
      // signs in so the token row follows the active account.
      FirebaseMessaging.instance.onTokenRefresh.listen((_) => registerToken());
      supabase.auth.onAuthStateChange.listen((state) {
        if (state.event == AuthChangeEvent.signedIn) registerToken();
      });
      await registerToken();
    } catch (e) {
      debugPrint('Push setup skipped: $e');
    }
  }

  /// Saves this device's FCM token against the signed-in user.
  static Future<void> registerToken() async {
    if (!_initialized) return;
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;
      await supabase.from('device_push_tokens').upsert({
        'token': token,
        'user_id': uid,
        'platform': defaultTargetPlatform.name.toLowerCase(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'token');
    } catch (e) {
      debugPrint('Could not register push token: $e');
    }
  }
}

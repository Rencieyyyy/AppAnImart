import 'package:firebase_core/firebase_core.dart';

/// Firebase project settings for push notifications.
///
/// PLACEHOLDERS — fill these in from your Firebase project before push
/// notifications can work (the app runs fine without them; push is simply
/// disabled until they are set):
///
///  1. Go to https://console.firebase.google.com and create (or open) the
///     AniMart project.
///  2. Add an Android app with package name `com.example.ani_mart` (see
///     android/app/build.gradle.kts → applicationId).
///  3. Project settings → General → "Your apps" shows every value below.
///     Alternatively run `flutterfire configure`, which generates them.
///
/// `PushService.init()` checks [isConfigured] and skips Firebase entirely
/// while these placeholders remain, so the app never crashes on startup.
class DefaultFirebaseOptions {
  DefaultFirebaseOptions._();

  static const String _placeholder = 'REPLACE_ME';

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: _placeholder, // Firebase console → General → Web API Key
    appId: _placeholder, // e.g. 1:1234567890:android:abc123
    messagingSenderId: _placeholder, // Cloud Messaging → Sender ID
    projectId: _placeholder, // e.g. animart-12345
    storageBucket: _placeholder, // e.g. animart-12345.appspot.com
  );

  /// Whether real Firebase values have been filled in.
  static bool get isConfigured =>
      android.apiKey != _placeholder && android.projectId != _placeholder;
}

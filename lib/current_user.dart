import 'main.dart';

/// Fetches the display name of the currently signed-in user from the `users`
/// table.
///
/// Falls back to the email local-part (the bit before `@`) and finally to
/// `'AniMart User'` if no name is available. Safe to call from any screen.
Future<String> fetchCurrentUserName() async {
  final user = supabase.auth.currentUser;
  if (user == null) return 'AniMart User';

  try {
    final row = await supabase
        .from('users')
        .select('name')
        .eq('id', user.id)
        .maybeSingle();
    final name = (row?['name'] as String?)?.trim();
    if (name != null && name.isNotEmpty) return name;
  } catch (_) {
    // Ignore and fall back to the auth email below.
  }

  final email = user.email ?? '';
  return email.isNotEmpty ? email.split('@').first : 'AniMart User';
}

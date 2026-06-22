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

/// Backfills the signed-in user's `valid_id_url` / `id_type` into the `users`
/// table from the values stashed in their Auth metadata at sign-up.
///
/// The sign-up flow uploads the valid-ID photo to Cloudinary and carries its
/// URL in the Auth metadata (no DB write happens then, since email
/// confirmation may leave the user without a session). On first login a
/// session is guaranteed, so this copies those values onto the row once.
///
/// Best-effort and idempotent: it only writes when the row is still missing
/// the URL, and silently does nothing if the columns don't exist yet.
Future<void> backfillValidIdFromMetadata() async {
  final user = supabase.auth.currentUser;
  if (user == null) return;

  final meta = user.userMetadata ?? const {};
  final idUrl = (meta['valid_id_url'] as String?)?.trim();
  if (idUrl == null || idUrl.isEmpty) return;
  final idType = (meta['id_type'] as String?)?.trim();

  try {
    final row = await supabase
        .from('users')
        .select('valid_id_url')
        .eq('id', user.id)
        .maybeSingle();
    final existing = (row?['valid_id_url'] as String?)?.trim();
    if (existing != null && existing.isNotEmpty) return; // already set

    await supabase.from('users').update({
      'valid_id_url': idUrl,
      if (idType != null && idType.isNotEmpty) 'id_type': idType,
    }).eq('id', user.id);
  } catch (_) {
    // Columns may not exist yet, or RLS may block it — ignore so login
    // still succeeds.
  }
}

import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Uploads image [bytes] to Cloudinary using an unsigned upload preset and
/// returns the hosted `secure_url` (or null if the upload fails).
///
/// Bytes are used instead of a `File` so this works on every platform,
/// including Flutter Web where `dart:io` File is unavailable.
///
/// [folder] controls which Cloudinary folder the image lands in. Listing
/// photos use the default `Animart`; sensitive uploads such as sign-up valid
/// IDs pass their own folder (e.g. `Animart/valid_ids`) to keep them separate.
Future<String?> uploadToCloudinary(
  Uint8List bytes,
  String filename, {
  String folder = 'Animart',
}) async {
  const String cloudName = "dor6aqawk";
  const String uploadPreset = "Animart";

  final url = Uri.parse(
    'https://api.cloudinary.com/v1_1/$cloudName/image/upload',
  );

  final request = http.MultipartRequest('POST', url)
    ..fields['upload_preset'] = uploadPreset
    ..fields['folder'] = folder
    ..files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: filename),
    );

  final response = await request.send();

  if (response.statusCode == 200) {
    final responseString = await response.stream.bytesToString();
    final jsonResponse = jsonDecode(responseString);
    return jsonResponse['secure_url'];
  } else {
    return null;
  }
}

/// Best-effort deletion of a listing's Cloudinary images.
///
/// Calls the `delete-cloudinary-image` Edge Function with only the
/// [listingId]. The function verifies (server-side) that the signed-in user
/// owns the listing and derives the image public_ids from the database row,
/// so the client can never ask to delete arbitrary images. The Cloudinary API
/// secret stays on the server.
///
/// Returns true if the function ran without throwing. Image cleanup failures
/// are swallowed so they never block the listing deletion itself.
Future<bool> deleteListingImages(String listingId) async {
  if (listingId.trim().isEmpty) return true;

  try {
    await Supabase.instance.client.functions.invoke(
      'delete-cloudinary-image',
      body: {'listing_id': listingId},
    );
    return true;
  } catch (_) {
    return false;
  }
}

/// Best-effort deletion of the signed-in user's current profile picture from
/// Cloudinary. Call this when replacing the avatar so the old image doesn't
/// linger. The Edge Function takes no input — it deletes whatever is stored in
/// the caller's own `users.avatar_url`, so it can only ever delete their own
/// image. Run it while the DB still holds the OLD url (before persisting the
/// new one). Failures are swallowed so they never block the avatar update.
Future<bool> deleteCurrentAvatarImage() async {
  try {
    await Supabase.instance.client.functions.invoke('delete-avatar-image');
    return true;
  } catch (_) {
    return false;
  }
}

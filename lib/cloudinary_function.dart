import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

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

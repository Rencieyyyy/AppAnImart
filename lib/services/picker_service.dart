import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

class ImageService {
  final ImagePicker _picker = ImagePicker();

  Future<File?> pickImage(ImageSource source) async {
    try {
      final XFile? selectedImage = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1080,
      );

      if (selectedImage != null) {
        return File(selectedImage.path);
      }
    } catch (e) {
      debugPrint('Error picking image: $e'); // fixes the "don't use print" warning
    }
    return null;
  }
}
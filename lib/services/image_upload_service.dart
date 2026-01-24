import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Service for handling image upload operations.
/// Extracted to avoid code duplication across dialogs.
class ImageUploadService {
  static final ImageUploadService _instance = ImageUploadService._internal();
  factory ImageUploadService() => _instance;
  ImageUploadService._internal();

  /// Picks an image from gallery and uploads it to Firebase Storage.
  /// 
  /// Returns the download URL of the uploaded image, or null if cancelled/failed.
  /// 
  /// [maxFileSizeBytes] - Maximum allowed file size (default 2MB)
  Future<String?> pickAndUploadImage({
    required BuildContext context,
    required String storageFolder,
    int quality = 90,
    int maxWidth = 1200,
    int maxHeight = 1200,
    int maxFileSizeBytes = 2 * 1024 * 1024, // 2MB default
  }) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: maxWidth.toDouble(),
        maxHeight: maxHeight.toDouble(),
        imageQuality: quality,
      );

      if (image == null) return null;

      // Check if context is still valid
      if (!context.mounted) return null;

      // ✅ Fix 7: Validate file size before upload
      final File imageFile = File(image.path);
      final int fileSizeBytes = await imageFile.length();
      
      if (fileSizeBytes > maxFileSizeBytes) {
        final double fileSizeMB = fileSizeBytes / (1024 * 1024);
        final double maxSizeMB = maxFileSizeBytes / (1024 * 1024);
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '❌ Image too large (${fileSizeMB.toStringAsFixed(1)}MB). '
                'Maximum size is ${maxSizeMB.toStringAsFixed(0)}MB.',
              ),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
        }
        return null;
      }

      // Show upload progress dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Uploading image...'),
            ],
          ),
        ),
      );

      final String downloadUrl = await _uploadImage(
        image.path,
        storageFolder,
      );

      // Dismiss loading dialog
      if (context.mounted) {
        Navigator.of(context).pop();
      }

      return downloadUrl;
    } catch (e) {
      // Dismiss loading dialog if still showing
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      debugPrint('ImageUploadService error: $e');
      return null;
    }
  }

  /// Uploads an image file to Firebase Storage and returns the download URL.
  Future<String> _uploadImage(
    String imagePath,
    String storageFolder,
  ) async {
    final File imageFile = File(imagePath);
    final String fileName =
        '${DateTime.now().millisecondsSinceEpoch}_${imageFile.uri.pathSegments.last}';
    final String storagePath = '$storageFolder/$fileName';

    final Reference storageRef =
        FirebaseStorage.instance.ref().child(storagePath);
    final UploadTask uploadTask = storageRef.putFile(imageFile);

    final TaskSnapshot snapshot = await uploadTask;
    final String downloadUrl = await snapshot.ref.getDownloadURL();

    return downloadUrl;
  }
}

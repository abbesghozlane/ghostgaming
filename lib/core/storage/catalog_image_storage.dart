import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/operation_id.dart';

class CatalogImageStorage {
  CatalogImageStorage(this._client);

  static const bucket = 'venue-catalog-images';
  static const maxImageBytes = 5 * 1024 * 1024;

  final SupabaseClient _client;
  final ImagePicker _picker = ImagePicker();

  Future<String?> pickAndUpload({required String venueId}) async {
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1800,
      imageQuality: 85,
    );
    if (image == null) return null;

    final extension = _supportedExtension(image);
    final bytes = await image.readAsBytes();
    if (bytes.length > maxImageBytes) {
      throw const CatalogImageException(
        'L’image dépasse la taille maximale de 5 Mo.',
      );
    }

    final path = '$venueId/${OperationId.create()}.$extension';
    await _client.storage
        .from(bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: switch (extension) {
              'jpg' => 'image/jpeg',
              'png' => 'image/png',
              'webp' => 'image/webp',
              _ => throw const CatalogImageException(
                'Format d’image non pris en charge.',
              ),
            },
          ),
        );
    return _client.storage.from(bucket).getPublicUrl(path);
  }

  String _supportedExtension(XFile image) {
    final mimeType = image.mimeType?.toLowerCase();
    if (mimeType == 'image/jpeg') return 'jpg';
    if (mimeType == 'image/png') return 'png';
    if (mimeType == 'image/webp') return 'webp';

    final extension = image.name.split('.').last.toLowerCase();
    if (extension == 'jpeg') return 'jpg';
    if (const {'jpg', 'png', 'webp'}.contains(extension)) return extension;
    throw const CatalogImageException('Choisissez une image JPG, PNG ou WebP.');
  }
}

class CatalogImageException implements Exception {
  const CatalogImageException(this.message);

  final String message;

  @override
  String toString() => message;
}

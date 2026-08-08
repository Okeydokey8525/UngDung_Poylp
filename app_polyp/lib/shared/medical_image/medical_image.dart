import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

const int maxMedicalImageBytes = 10 * 1024 * 1024;

final class SelectedMedicalImage {
  const SelectedMedicalImage({
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
    required this.width,
    required this.height,
    required this.bytes,
  });

  final String name;
  final String mimeType;
  final int sizeBytes;
  final int width;
  final int height;
  final Uint8List bytes;
}

abstract interface class MedicalImagePicker {
  Future<XFile?> pickFromGallery();
}

final class GalleryMedicalImagePicker implements MedicalImagePicker {
  GalleryMedicalImagePicker(this._picker);

  final ImagePicker _picker;

  @override
  Future<XFile?> pickFromGallery() =>
      _picker.pickImage(source: ImageSource.gallery);
}

final medicalImagePickerProvider = Provider<MedicalImagePicker>(
  (ref) => GalleryMedicalImagePicker(ImagePicker()),
);

final class MedicalImageValidator {
  const MedicalImageValidator._();

  static Future<SelectedMedicalImage> validate(XFile file) async {
    final extension = _extension(file.name);
    if (!const {'jpg', 'jpeg', 'png'}.contains(extension)) {
      throw const MedicalImageValidationException(
        'Chỉ hỗ trợ ảnh JPG, JPEG hoặc PNG.',
      );
    }

    final reportedSize = await file.length();
    if (reportedSize <= 0) {
      throw const MedicalImageValidationException('Tệp ảnh không hợp lệ.');
    }
    if (reportedSize > maxMedicalImageBytes) {
      throw const MedicalImageValidationException(
        'Ảnh vượt quá dung lượng 10 MB.',
      );
    }

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || bytes.length != reportedSize) {
      throw const MedicalImageValidationException('Tệp ảnh không hợp lệ.');
    }
    if (bytes.length > maxMedicalImageBytes) {
      throw const MedicalImageValidationException(
        'Ảnh vượt quá dung lượng 10 MB.',
      );
    }

    final metadata = _readMetadata(bytes);
    final expectedMime = extension == 'png' ? 'image/png' : 'image/jpeg';
    if (metadata == null || metadata.mimeType != expectedMime) {
      throw const MedicalImageValidationException('Tệp ảnh không hợp lệ.');
    }
    final reportedMime = file.mimeType?.toLowerCase().split(';').first.trim();
    if (reportedMime != null &&
        reportedMime.isNotEmpty &&
        reportedMime != metadata.mimeType) {
      throw const MedicalImageValidationException(
        'Chỉ hỗ trợ ảnh JPG, JPEG hoặc PNG.',
      );
    }

    return SelectedMedicalImage(
      name: file.name,
      mimeType: metadata.mimeType,
      sizeBytes: bytes.length,
      width: metadata.width,
      height: metadata.height,
      bytes: bytes,
    );
  }

  static String _extension(String name) {
    final normalized = name.replaceAll('\\', '/').split('/').last;
    final index = normalized.lastIndexOf('.');
    return index < 0 ? '' : normalized.substring(index + 1).toLowerCase();
  }

  static _ImageMetadata? _readMetadata(Uint8List bytes) {
    if (_isPng(bytes)) {
      final width = _uint32(bytes, 16);
      final height = _uint32(bytes, 20);
      if (width > 0 && height > 0) {
        return _ImageMetadata('image/png', width, height);
      }
      return null;
    }
    if (bytes.length >= 4 && bytes[0] == 0xff && bytes[1] == 0xd8) {
      final dimensions = _jpegDimensions(bytes);
      if (dimensions != null) {
        return _ImageMetadata('image/jpeg', dimensions.$1, dimensions.$2);
      }
    }
    return null;
  }

  static bool _isPng(Uint8List bytes) {
    const signature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
    if (bytes.length < 24) return false;
    for (var index = 0; index < signature.length; index++) {
      if (bytes[index] != signature[index]) return false;
    }
    return true;
  }

  static int _uint32(Uint8List bytes, int offset) =>
      (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];

  static (int, int)? _jpegDimensions(Uint8List bytes) {
    var offset = 2;
    const startOfFrameMarkers = {
      0xc0,
      0xc1,
      0xc2,
      0xc3,
      0xc5,
      0xc6,
      0xc7,
      0xc9,
      0xca,
      0xcb,
      0xcd,
      0xce,
      0xcf,
    };
    while (offset + 3 < bytes.length) {
      if (bytes[offset] != 0xff) {
        offset++;
        continue;
      }
      while (offset < bytes.length && bytes[offset] == 0xff) {
        offset++;
      }
      if (offset >= bytes.length) return null;
      final marker = bytes[offset++];
      if (marker == 0xd8 || marker == 0xd9) continue;
      if (marker == 0xda || offset + 1 >= bytes.length) return null;
      final length = (bytes[offset] << 8) | bytes[offset + 1];
      if (length < 2 || offset + length > bytes.length) return null;
      if (startOfFrameMarkers.contains(marker) && length >= 7) {
        final height = (bytes[offset + 3] << 8) | bytes[offset + 4];
        final width = (bytes[offset + 5] << 8) | bytes[offset + 6];
        return width > 0 && height > 0 ? (width, height) : null;
      }
      offset += length;
    }
    return null;
  }
}

final class MedicalImageValidationException implements Exception {
  const MedicalImageValidationException(this.message);

  final String message;
}

final class _ImageMetadata {
  const _ImageMetadata(this.mimeType, this.width, this.height);

  final String mimeType;
  final int width;
  final int height;
}

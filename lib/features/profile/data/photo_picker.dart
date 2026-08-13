import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// A photo picked from the device, as raw bytes ready for upload.
class PickedPhoto {
  const PickedPhoto({required this.bytes, required this.name});

  final Uint8List bytes;
  final String name;
}

/// Abstraction over device photo picking so the UI can be tested with a fake.
abstract interface class ProfilePhotoPicker {
  /// Returns the picked photo, or null when the user cancels.
  Future<PickedPhoto?> pickPhoto();
}

/// Production picker backed by [ImagePicker]. Downscales and compresses the
/// image before upload to keep transfers small.
class DevicePhotoPicker implements ProfilePhotoPicker {
  const DevicePhotoPicker();

  @override
  Future<PickedPhoto?> pickPhoto() async {
    final XFile? file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (file == null) return null;
    return PickedPhoto(bytes: await file.readAsBytes(), name: file.name);
  }
}

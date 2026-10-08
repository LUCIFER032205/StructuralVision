import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('structural_vision/orientation');

/// Takes a photo whose EXIF orientation matches how the phone was physically
/// held. The camera plugin tags from the screen rotation, which stays portrait
/// with auto-rotate off, so landscape shots came out sideways (and the backend,
/// which bakes the tag into the pixels, then missed the cracks).
Future<Uint8List> takeUprightPicture(CameraController ctrl) async {
  int? rotation;
  try {
    rotation = await _channel.invokeMethod<int>('deviceRotation');
  } catch (_) {} // no sensor / channel: keep the plugin's tag
  final bytes = await (await ctrl.takePicture()).readAsBytes();
  if (rotation == null) return bytes;
  // Back camera: Android's documented JPEG_ORIENTATION formula.
  return withExifOrientation(bytes, (ctrl.description.sensorOrientation + rotation) % 360);
}

/// Rewrites the EXIF orientation tag of [jpeg] to rotate it [degrees]
/// clockwise on display. Only patches the existing 2-byte tag, never
/// re-encodes. Returns [jpeg] unchanged if there is no tag, or if it is
/// already 1: that device rotated the pixels itself.
// ponytail: no tag -> left alone; insert one if a phone turns up that omits it.
Uint8List withExifOrientation(Uint8List jpeg, int degrees) {
  final value = const {0: 1, 90: 6, 180: 3, 270: 8}[degrees];
  if (value == null) return jpeg;
  try {
    final b = ByteData.sublistView(jpeg);
    if (b.getUint16(0) != 0xFFD8) return jpeg;
    var p = 2;
    while (jpeg[p] == 0xFF && jpeg[p + 1] != 0xDA) { // stop at start-of-scan
      final len = b.getUint16(p + 2);
      if (jpeg[p + 1] == 0xE1 && String.fromCharCodes(jpeg, p + 4, p + 8) == 'Exif') {
        final tiff = p + 10;
        final endian = jpeg[tiff] == 0x49 ? Endian.little : Endian.big;
        final ifd = tiff + b.getUint32(tiff + 4, endian);
        for (var i = 0; i < b.getUint16(ifd, endian); i++) {
          final e = ifd + 2 + i * 12;
          if (b.getUint16(e, endian) != 0x0112) continue;
          if (b.getUint16(e + 8, endian) == 1) return jpeg;
          final out = Uint8List.fromList(jpeg);
          ByteData.sublistView(out).setUint16(e + 8, value, endian);
          return out;
        }
        return jpeg;
      }
      p += 2 + len;
    }
  } on RangeError {
    // truncated / odd JPEG: leave it as the camera wrote it
  }
  return jpeg;
}

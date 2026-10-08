import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:structural_vision_ar/photo_orientation.dart';

/// SOI + APP1 "Exif" with one IFD0 entry (orientation = [tag]) + SOS.
Uint8List _jpeg(int tag, {bool little = true}) {
  final tiff = ByteData(8 + 2 + 12 + 4);
  final e = little ? Endian.little : Endian.big;
  tiff.setUint16(0, little ? 0x4949 : 0x4D4D);
  tiff.setUint16(2, 42, e);
  tiff.setUint32(4, 8, e);
  tiff.setUint16(8, 1, e);
  tiff.setUint16(10, 0x0112, e);
  tiff.setUint16(12, 3, e);
  tiff.setUint32(14, 1, e);
  tiff.setUint16(18, tag, e);
  final body = [...'Exif'.codeUnits, 0, 0, ...tiff.buffer.asUint8List()];
  final len = body.length + 2;
  return Uint8List.fromList(
      [0xFF, 0xD8, 0xFF, 0xE1, len >> 8, len & 0xFF, ...body, 0xFF, 0xDA, 0, 2]);
}

int _tagOf(Uint8List j, {bool little = true}) => ByteData.sublistView(j)
    .getUint16(12 + 18, little ? Endian.little : Endian.big);

void main() {
  test('rewrites the orientation tag for each rotation, both byte orders', () {
    for (final little in [true, false]) {
      final src = _jpeg(6, little: little);
      for (final (deg, tag) in [(0, 1), (90, 6), (180, 3), (270, 8)]) {
        expect(_tagOf(withExifOrientation(src, deg), little: little), tag);
      }
      expect(_tagOf(src, little: little), 6, reason: 'input is not mutated');
    }
  });

  test('leaves already-upright and non-JPEG bytes alone', () {
    final upright = _jpeg(1);
    expect(identical(withExifOrientation(upright, 90), upright), isTrue);
    final junk = Uint8List.fromList([1, 2, 3]);
    expect(identical(withExifOrientation(junk, 90), junk), isTrue);
  });
}

import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// LSB Steganography: hides UTF-8 bytes in PNG RGB channels (1 bit per channel)
/// Header: 4 bytes length (big endian) + payload, bit-packed into LSBs
class StegoService {
  static const _headerBytes = 4;

  /// Embed [message] into [pngBytes] (must be PNG). Returns new PNG bytes.
  /// Throws if image too small.
  static Uint8List embedMessage(Uint8List pngBytes, String message) {
    final image = img.decodeImage(pngBytes);
    if (image == null) throw ArgumentError('Invalid image');
    final msgBytes = Uint8List.fromList([..._int32ToBytes(message.length), ...Uint8List.fromList(message.codeUnits)]);
    // Need bit capacity: width*height*3 bits, we use 1 bit per channel (R,G,B)
    final capacityBits = image.width * image.height * 3;
    final neededBits = msgBytes.length * 8;
    if (neededBits > capacityBits) {
      throw ArgumentError('Image too small: needs $neededBits bits, has $capacityBits');
    }
    int bitIdx = 0;
    for (int y = 0; y < image.height && bitIdx < neededBits; y++) {
      for (int x = 0; x < image.width && bitIdx < neededBits; x++) {
        final pixel = image.getPixel(x, y);
        int r = pixel.r.toInt();
        int g = pixel.g.toInt();
        int b = pixel.b.toInt();
        for (final channel in [0, 1, 2]) { // R,G,B
          if (bitIdx >= neededBits) break;
          final byteIdx = bitIdx ~/ 8;
          final bitPos = 7 - (bitIdx % 8);
          final bit = (msgBytes[byteIdx] >> bitPos) & 1;
          if (channel == 0) r = (r & 0xFE) | bit;
          if (channel == 1) g = (g & 0xFE) | bit;
          if (channel == 2) b = (b & 0xFE) | bit;
          bitIdx++;
        }
        image.setPixelRgb(x, y, r, g, b);
        // keep alpha
        // image.setPixel with alpha would need setPixel; using setPixelRgb keeps alpha 255, so restore:
        final p2 = image.getPixel(x, y);
        image.setPixel(x, y, p2);
      }
    }
    final out = img.encodePng(image);
    return Uint8List.fromList(out);
  }

  /// Extract hidden message from [pngBytes]. Returns string or throws.
  static String extractMessage(Uint8List pngBytes) {
    final image = img.decodeImage(pngBytes);
    if (image == null) throw ArgumentError('Invalid image');
    // First read 4 bytes header = 32 bits
    Uint8List header = Uint8List(4);
    // Helper to read next bit
    int readBit(int idx) {
      int y = (idx ~/ 3) ~/ image.width;
      int x = (idx ~/ 3) % image.width;
      int channel = idx % 3;
      final p = image.getPixel(x, y);
      if (channel == 0) return p.r.toInt() & 1;
      if (channel == 1) return p.g.toInt() & 1;
      return p.b.toInt() & 1;
    }
    // Read header
    for (int i = 0; i < 32; i++) {
      int bit = readBit(i);
      int byteIdx = i ~/ 8;
      int bitPos = 7 - (i % 8);
      header[byteIdx] |= (bit << bitPos);
    }
    int msgLen = (header[0] << 24) | (header[1] << 16) | (header[2] << 8) | header[3];
    if (msgLen < 0 || msgLen > 100000) throw FormatException('Invalid stego length $msgLen');
    final totalBits = (_headerBytes + msgLen) * 8;
    final capacity = image.width * image.height * 3;
    if (totalBits > capacity) throw FormatException('Stego payload exceeds capacity');
    final payload = Uint8List(msgLen);
    for (int i = 32; i < totalBits; i++) {
      int bit = readBit(i);
      int payloadBitIdx = i - 32;
      int byteIdx = payloadBitIdx ~/ 8;
      int bitPos = 7 - (payloadBitIdx % 8);
      payload[byteIdx] |= (bit << bitPos);
    }
    return String.fromCharCodes(payload);
  }

  static List<int> _int32ToBytes(int v) => [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];

  // Generate a 320x240 carrier PNG for demo (gradient)
  static Uint8List generateCarrier({int w = 320, int h = 240}) {
    final image = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        int r = (x * 255 ~/ w);
        int g = (y * 255 ~/ h);
        int b = 128 + (x + y) % 64;
        image.setPixelRgb(x, y, r, g, b);
      }
    }
    return Uint8List.fromList(img.encodePng(image));
  }
}

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto_lib;


class FileChunk {
  final int index;
  final int totalChunks;
  final Uint8List data;
  final String hash;

  FileChunk({
    required this.index,
    required this.totalChunks,
    required this.data,
    required this.hash,
  });
}


class FileManifest {
  final String fileId;
  final String fileName;
  final int totalSize;
  final int totalChunks;
  final List<String> chunkHashes;
  final Uint8List encryptionKey;
  final DateTime createdAt;
  final int ttlHours;

  FileManifest({
    required this.fileId,
    required this.fileName,
    required this.totalSize,
    required this.totalChunks,
    required this.chunkHashes,
    required this.encryptionKey,
    required this.createdAt,
    this.ttlHours = 24,
  });
}


class ChunkUploadResult {
  final int chunkIndex;
  final String chunkUrl;
  final bool success;
  final String? error;

  ChunkUploadResult({
    required this.chunkIndex,
    required this.chunkUrl,
    this.success = true,
    this.error,
  });
}



class DecentralizedFileClient {
  static const int maxChunkSize = 10 * 1024 * 1024;
  static const int maxFileSize = 100 * 1024 * 1024;

  final Random _random = Random.secure();


  ({FileManifest manifest, List<FileChunk> chunks}) splitFile(
    Uint8List fileData,
    String fileName,
  ) {
    if (fileData.length > maxFileSize) {
      throw ArgumentError(
        'File size ${fileData.length} exceeds maximum of $maxFileSize bytes',
      );
    }


    final fileIdBytes = List<int>.generate(16, (_) => _random.nextInt(256));
    final fileId = fileIdBytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final encryptionKey = Uint8List.fromList(
      List<int>.generate(32, (_) => _random.nextInt(256)),
    );


    final totalChunks = (fileData.length / maxChunkSize).ceil();
    final chunks = <FileChunk>[];
    final chunkHashes = <String>[];

    for (int i = 0; i < totalChunks; i++) {
      final start = i * maxChunkSize;
      final end = (start + maxChunkSize).clamp(0, fileData.length);
      final chunkData = Uint8List.fromList(fileData.sublist(start, end));


      final encrypted = _xorEncrypt(chunkData, encryptionKey);


      final hash = crypto_lib.sha256.convert(encrypted).toString();

      chunks.add(FileChunk(
        index: i,
        totalChunks: totalChunks,
        data: encrypted,
        hash: hash,
      ));
      chunkHashes.add(hash);
    }

    final manifest = FileManifest(
      fileId: fileId,
      fileName: fileName,
      totalSize: fileData.length,
      totalChunks: totalChunks,
      chunkHashes: chunkHashes,
      encryptionKey: encryptionKey,
      createdAt: DateTime.now(),
    );

    return (manifest: manifest, chunks: chunks);
  }


  Uint8List reassembleFile(FileManifest manifest, List<FileChunk> chunks) {

    final sorted = List<FileChunk>.from(chunks)
      ..sort((a, b) => a.index.compareTo(b.index));

    if (sorted.length != manifest.totalChunks) {
      throw StateError(
        'Missing chunks: got ${sorted.length}, expected ${manifest.totalChunks}',
      );
    }


    for (int i = 0; i < sorted.length; i++) {
      final expectedHash = manifest.chunkHashes[i];
      final actualHash = crypto_lib.sha256.convert(sorted[i].data).toString();
      if (actualHash != expectedHash) {
        throw StateError('Chunk $i integrity check failed');
      }
    }


    final decryptedChunks = sorted.map(
      (chunk) => _xorEncrypt(chunk.data, manifest.encryptionKey),
    );

    final totalLength = decryptedChunks.fold<int>(0, (sum, c) => sum + c.length);
    final result = Uint8List(totalLength);
    int offset = 0;
    for (final chunk in decryptedChunks) {
      result.setAll(offset, chunk);
      offset += chunk.length;
    }

    return result.sublist(0, manifest.totalSize);
  }


  Future<ChunkUploadResult> uploadChunk(FileChunk chunk) async {

    final delayMs = (chunk.data.length / (1024 * 100)).ceil();
    await Future.delayed(Duration(milliseconds: delayMs.clamp(50, 2000)));

    final nodeId = _random.nextInt(100).toString().padLeft(3, '0');
    return ChunkUploadResult(
      chunkIndex: chunk.index,
      chunkUrl: 'swarm:
    );
  }


  Future<FileChunk> downloadChunk(String chunkUrl, int index, int totalChunks) async {
    await Future.delayed(Duration(milliseconds: 100 + _random.nextInt(200)));


    return FileChunk(
      index: index,
      totalChunks: totalChunks,
      data: Uint8List.fromList(List<int>.generate(1024, (_) => _random.nextInt(256))),
      hash: chunkUrl.split('/').last,
    );
  }


  Uint8List _xorEncrypt(Uint8List data, Uint8List key) {
    final result = Uint8List(data.length);
    for (int i = 0; i < data.length; i++) {
      result[i] = data[i] ^ key[i % key.length];
    }
    return result;
  }
}

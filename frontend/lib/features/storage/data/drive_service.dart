import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/dio_client.dart';

final driveServiceProvider = Provider<DriveService>((ref) {
  return DriveService(ref.watch(dioProvider));
});

class DriveService {
  final Dio _dio;

  DriveService(this._dio);

  Future<List<dynamic>> getFiles() async {
    try {
      final response = await _dio.get('/storage/files?provider=SUPABASE');
      return response.data;
    } catch (e) {
      return [];
    }
  }

  Future<bool> uploadFile(String fileName, int size, String path) async {
    try {
      // 1. Encrypt file (TODO: Integrate EncryptionService)
      // 2. Upload to Supabase Storage (Mocking metadata save for now)
      final response = await _dio.post('/storage/metadata', data: {
        'fileName': fileName,
        'fileSize': size,
        'storagePath': path,
        'storageProvider': 'SUPABASE',
        'isEncrypted': true,
      });
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}

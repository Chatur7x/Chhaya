import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';

final sharingServiceProvider = Provider<SharingService>((ref) {
  return SharingService(ref.watch(dioProvider));
});

class SharingService {
  final Dio _dio;

  SharingService(this._dio);

  Future<Map<String, dynamic>?> generateLink(int fileId, {String? password, int? expiryDays, int? limit}) async {
    try {
      final response = await _dio.post('/share/generate', data: {
        'fileId': fileId,
        if (password != null) 'password': password,
        if (expiryDays != null) 'expiryDays': expiryDays,
        if (limit != null) 'limit': limit,
      });
      return response.data;
    } catch (e) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> getLinkInfo(String token) async {
    try {
      final response = await _dio.get('/share/info/$token');
      return response.data;
    } catch (e) {
      return null;
    }
  }
}

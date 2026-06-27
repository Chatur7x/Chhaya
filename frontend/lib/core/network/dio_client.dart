import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const String _env = 'LOCAL'; // Change to 'EMULATOR' or 'PHYSICAL' as needed
const String _physicalIp = '192.168.1.5'; // Update this to your local IP for physical devices

String _getBaseUrl() {
  switch (_env) {
    case 'EMULATOR':
      return 'http://10.0.2.2:8080/api';
    case 'PHYSICAL':
      return 'http://$_physicalIp:8080/api';
    case 'LOCAL':
    default:
      return 'http://localhost:8080/api';
  }
}

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: _getBaseUrl(),
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 3),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ),
  );

  // Add interceptor for logging/auth if needed
  dio.interceptors.add(LogInterceptor(responseBody: true, requestBody: true));
  
  return dio;
});

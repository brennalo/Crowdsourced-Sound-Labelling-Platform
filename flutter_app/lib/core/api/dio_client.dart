import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import '../../config.dart';

const _tokenKey = 'auth_token';
const _storage = FlutterSecureStorage();

Dio buildDioClient() {
  final dio = Dio(BaseOptions(
    baseUrl: AppConfig.baseUrl,
    connectTimeout: AppConfig.httpTimeout,
    receiveTimeout: AppConfig.httpTimeout,
    headers: {'Content-Type': 'application/json'},
  ));

  dio.interceptors.add(_AuthInterceptor());
  dio.interceptors.add(PrettyDioLogger(
    requestHeader: false,
    requestBody: true,
    responseBody: true,
    compact: true,
  ));

  return dio;
}

class _AuthInterceptor extends Interceptor {
  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _storage.read(key: _tokenKey);
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // Let callers handle 401 — providers will redirect to login
    handler.next(err);
  }
}

// Token helpers used by auth provider
Future<void> saveToken(String token) => _storage.write(key: _tokenKey, value: token);
Future<void> clearToken() => _storage.delete(key: _tokenKey);
Future<String?> readToken() => _storage.read(key: _tokenKey);

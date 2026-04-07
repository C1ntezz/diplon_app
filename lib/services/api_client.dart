import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../app_config.dart';

class ApiClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  
  String get baseUrl => AppConfig.baseUrl.endsWith('/') 
        ? AppConfig.baseUrl.substring(0, AppConfig.baseUrl.length - 1) 
        : AppConfig.baseUrl;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    String? token = await _storage.read(key: 'accessToken') ?? await _storage.read(key: 'jwt_token');
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    http.StreamedResponse response = await _inner.send(request);

    if (response.statusCode == 401 && !request.url.path.contains('/api/auth/login') && !request.url.path.contains('/api/auth/register')) {
      print('⚠️ Access Token истек. Пытаемся обновить...');
      bool isRefreshed = await refreshToken();
      
      if (isRefreshed) {
        print('✅ Токен успешно обновлен в фоне!');
        final newRequest = _copyRequest(request);
        String? newToken = await _storage.read(key: 'accessToken');
        newRequest.headers['Authorization'] = 'Bearer $newToken';
        
        return _inner.send(newRequest);
      } else {
        await _storage.delete(key: 'jwt_token');
        await _storage.delete(key: 'accessToken');
        await _storage.delete(key: 'refreshToken');
        await _storage.delete(key: 'userId');
        await _storage.delete(key: 'username');
        await _storage.delete(key: 'displayName');
        throw Exception('SessionExpired'); 
      }
    }

    return response;
  }

  Future<bool> refreshToken() async {
    try {
      String? refreshToken = await _storage.read(key: 'refreshToken');
      if (refreshToken == null) return false;

      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': refreshToken}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _storage.write(key: 'accessToken', value: data['accessToken']);
        await _storage.write(key: 'refreshToken', value: data['refreshToken']);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  http.BaseRequest _copyRequest(http.BaseRequest request) {
    if (request is http.Request) {
      final newRequest = http.Request(request.method, request.url)
        ..encoding = request.encoding
        ..bodyBytes = request.bodyBytes;
      newRequest.headers.addAll(request.headers);
      return newRequest;
    } else if (request is http.MultipartRequest) {
      final newRequest = http.MultipartRequest(request.method, request.url)
        ..fields.addAll(request.fields)
        ..files.addAll(request.files);
      newRequest.headers.addAll(request.headers);
      return newRequest;
    }
    throw UnimplementedError('Request copy not implemented');
  }
}

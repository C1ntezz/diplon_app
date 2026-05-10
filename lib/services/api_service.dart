import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';

import '../app_config.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/user.dart';
import 'api_client.dart';

class ApiService {
  final _storage = const FlutterSecureStorage();
  final _apiClient = ApiClient(); // Используем наш умный клиент

  String? token; // Это теперь accessToken
  String? refreshToken;
  String? userId;
  String? username;
  String? displayName;

  Future<void> loadSession() async {
    try {
      token = await _storage.read(key: 'accessToken') ?? await _storage.read(key: 'jwt_token');
      refreshToken = await _storage.read(key: 'refreshToken');
      userId = await _storage.read(key: 'userId');
      username = await _storage.read(key: 'username');
      displayName = await _storage.read(key: 'displayName');
    } catch (e) {
      print('⚠️ [loadSession] Keystore corrupted or reset, clearing storage: $e');
      token = null;
      refreshToken = null;
      userId = null;
      username = null;
      displayName = null;
      try {
        await _storage.delete(key: 'accessToken');
        await _storage.delete(key: 'jwt_token');
        await _storage.delete(key: 'refreshToken');
        await _storage.delete(key: 'userId');
        await _storage.delete(key: 'username');
        await _storage.delete(key: 'displayName');
      } catch (_) {}
    }
  }

  Future<void> saveSession({
    required String token,
    required String refreshToken,
    required String userId,
    required String username,
    required String displayName,
  }) async {
    this.token = token;
    this.refreshToken = refreshToken;
    this.userId = userId;
    this.username = username;
    this.displayName = displayName;

    await _storage.write(key: 'accessToken', value: token);
    await _storage.write(key: 'jwt_token', value: token); // Для обратной совместимости локально
    await _storage.write(key: 'refreshToken', value: refreshToken);
    await _storage.write(key: 'userId', value: userId);
    await _storage.write(key: 'username', value: username);
    await _storage.write(key: 'displayName', value: displayName);
  }

  Future<void> logout() async {
    try {
      // Отправляем запрос на сервер, чтобы "убить" рефреш токен в БД
      await _apiClient.post(_u('/api/auth/logout'), headers: {'Content-Type': 'application/json'});
    } catch (e) {
      print('Logout API error: $e');
    }

    token = null; refreshToken = null; userId = null; username = null; displayName = null;
    
    // Удаляем сессионные данные (НЕ deleteAll, чтобы ключи E2E остались)
    await _storage.delete(key: 'accessToken');
    await _storage.delete(key: 'jwt_token');
    await _storage.delete(key: 'refreshToken');
    await _storage.delete(key: 'userId');
    await _storage.delete(key: 'username');
    await _storage.delete(key: 'displayName');
  }

  Future<void> updateProfile({
    required String username,
    required String displayName,
  }) async {
    var u = username.trim();
    if (u.startsWith('@')) u = u.substring(1);
    final d = displayName.trim();

    final res = await _apiClient.put(
      _u('/api/auth/profile'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': u,
        'displayName': d.isNotEmpty ? d : u,
      }),
    );

    print('📡 [API] Update profile response: ${res.statusCode}');
    final data = res.body.isNotEmpty ? jsonDecode(res.body) as Map<String, dynamic> : <String, dynamic>{};

    if (res.statusCode != 200) {
      throw Exception(data['error'] ?? 'Update profile failed');
    }

    await saveSession(
      token: data['accessToken']?.toString() ?? data['token'].toString(),
      refreshToken: data['refreshToken']?.toString() ?? refreshToken ?? '',
      userId: data['userId']?.toString() ?? userId ?? '',
      username: data['username']?.toString() ?? u,
      displayName: data['displayName']?.toString() ?? d,
    );
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final res = await _apiClient.put(
      _u('/api/auth/password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      }),
    );

    print('📡 [API] Change password response: ${res.statusCode}');
    final data = res.body.isNotEmpty ? jsonDecode(res.body) : null;

    if (res.statusCode != 200) {
      if (data is Map && data['error'] != null) throw Exception(data['error']);
      throw Exception('Change password failed');
    }
  }

  Uri _u(String path, [Map<String, String>? q]) {
    final url = AppConfig.baseUrl.endsWith('/') 
        ? AppConfig.baseUrl.substring(0, AppConfig.baseUrl.length - 1) 
        : AppConfig.baseUrl;
    final uri = Uri.parse('$url$path').replace(queryParameters: q);
    print('📡 [API] ${DateTime.now().toIso8601String()} Request: $uri');
    return uri;
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    var u = username.trim();
    if (u.startsWith('@')) u = u.substring(1);

    final res = await http.post(
      _u('/api/auth/login'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'username': u, 'password': password}),
    );
    
    print('📡 [API] Login response: ${res.statusCode}');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) throw Exception(data['error'] ?? 'Login failed');
    return data;
  }

  Future<void> register(String username, String password, {String? displayName}) async {
    var u = username.trim();
    if (u.startsWith('@')) u = u.substring(1);

    final bodyMap = {
      'username': u,
      'password': password,
    };
    if (displayName != null) {
      bodyMap['displayName'] = displayName;
    }
    final res = await http.post(
      _u('/api/auth/register'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(bodyMap),
    );

    print('📡 [API] Register response: ${res.statusCode}');
    final body = res.body.isNotEmpty ? jsonDecode(res.body) : null;
    if (res.statusCode != 200 && res.statusCode != 201) {
      if (body is Map && body['error'] != null) throw Exception(body['error']);
      throw Exception('Register failed');
    }
  }

  Future<List<String>> getOnlineUsers() async {
    final res = await _apiClient.get(_u('/api/users/online'), headers: {'Content-Type': 'application/json'});
    print('📡 [API] Online users response: ${res.statusCode}');
    if (res.statusCode != 200) throw Exception('Failed online users');
    final arr = jsonDecode(res.body) as List;
    return arr.map((e) => e.toString()).toList();
  }

  Future<List<AppUser>> getUsers() async {
    final res = await _apiClient.get(_u('/api/users'), headers: {'Content-Type': 'application/json'});
    print('📡 [API] Get users response: ${res.statusCode}');
    if (res.statusCode != 200) throw Exception('Failed users');
    final arr = jsonDecode(res.body) as List;
    return arr.map((e) => AppUser.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Conversation>> getConversations() async {
    final res = await _apiClient.get(_u('/api/conversations'), headers: {'Content-Type': 'application/json'});
    print('📡 [API] Get conversations response: ${res.statusCode}');
    if (res.statusCode != 200) throw Exception('Failed conversations');
    final arr = jsonDecode(res.body) as List;
    return arr.map((e) => Conversation.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Conversation> createConversation(String otherUserId) async {
    final res = await _apiClient.post(
      _u('/api/conversations'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'participantIds': [otherUserId]}),
    );
    print('📡 [API] Create conversation response: ${res.statusCode}');
    final data = jsonDecode(res.body);
    if (res.statusCode != 200 && res.statusCode != 201) throw Exception('Create conversation failed');
    return Conversation.fromJson(data as Map<String, dynamic>);
  }

  Future<Conversation> createGroupConversation({
    required String name,
    required List<String> participantIds,
  }) async {
    final res = await _apiClient.post(
      _u('/api/conversations'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'type': 'group',
        'name': name,
        'participantIds': participantIds,
      }),
    );

    print('📡 [API] Create group response: ${res.statusCode}');
    final data = jsonDecode(res.body);
    if (res.statusCode != 200 && res.statusCode != 201) {
      if (data is Map && data['error'] != null) throw Exception(data['error']);
      throw Exception('Create group failed');
    }
    return Conversation.fromJson(data as Map<String, dynamic>);
  }

  Future<Conversation> updateGroupName({
    required String conversationId,
    required String name,
  }) async {
    final res = await _apiClient.put(
      _u('/api/conversations/$conversationId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name}),
    );

    print('📡 [API] Rename group response: ${res.statusCode}');
    final data = jsonDecode(res.body);
    if (res.statusCode != 200) {
      if (data is Map && data['error'] != null) throw Exception(data['error']);
      throw Exception('Rename group failed');
    }
    return Conversation.fromJson(data as Map<String, dynamic>);
  }

  Future<Conversation> updateGroupMemberRole({
    required String conversationId,
    required String targetUserId,
    required String role,
  }) async {
    final res = await _apiClient.put(
      _u('/api/conversations/$conversationId/roles'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'userId': targetUserId,
        'role': role,
      }),
    );

    print('📡 [API] Change group role response: ${res.statusCode}');
    final data = jsonDecode(res.body);
    if (res.statusCode != 200) {
      if (data is Map && data['error'] != null) throw Exception(data['error']);
      throw Exception('Change group role failed');
    }
    return Conversation.fromJson(data as Map<String, dynamic>);
  }

  Future<Conversation> addGroupMember({
    required String conversationId,
    required String userId,
  }) async {
    final res = await _apiClient.post(
      _u('/api/conversations/$conversationId/participants'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'userId': userId}),
    );

    print('📡 [API] Add group member response: ${res.statusCode}');
    final data = jsonDecode(res.body);
    if (res.statusCode != 200 && res.statusCode != 201) {
      if (data is Map && data['error'] != null) throw Exception(data['error']);
      throw Exception('Add group member failed');
    }
    return Conversation.fromJson(data as Map<String, dynamic>);
  }

  Future<Conversation> removeGroupMember({
    required String conversationId,
    required String userId,
  }) async {
    final res = await _apiClient.delete(
      _u('/api/conversations/$conversationId/participants/$userId'),
      headers: {'Content-Type': 'application/json'},
    );

    print('📡 [API] Remove group member response: ${res.statusCode}');
    final data = jsonDecode(res.body);
    if (res.statusCode != 200) {
      if (data is Map && data['error'] != null) throw Exception(data['error']);
      throw Exception('Remove group member failed');
    }
    return Conversation.fromJson(data as Map<String, dynamic>);
  }

  Future<void> leaveGroup({
    required String conversationId,
  }) async {
    final res = await _apiClient.delete(
      _u('/api/conversations/$conversationId/leave'),
      headers: {'Content-Type': 'application/json'},
    );

    print('📡 [API] Leave group response: ${res.statusCode}');
    final data = res.body.isNotEmpty ? jsonDecode(res.body) : null;
    if (res.statusCode != 200) {
      if (data is Map && data['error'] != null) throw Exception(data['error']);
      throw Exception('Leave group failed');
    }
  }

  Future<void> markConversationRead(String conversationId) async {
    final res = await _apiClient.post(
      _u('/api/conversations/$conversationId/read'),
      headers: {'Content-Type': 'application/json'},
    );

    print('📡 [API] Mark conversation read response: ${res.statusCode}');
    final data = res.body.isNotEmpty ? jsonDecode(res.body) : null;
    if (res.statusCode != 200) {
      if (data is Map && data['error'] != null) throw Exception(data['error']);
      throw Exception('Mark conversation read failed');
    }
  }

  Future<List<ChatMessage>> getMessages(String convId, {int limit = 50, String? before}) async {
    final q = <String, String>{'limit': limit.toString()};
    if (before != null) {
      q['before'] = before;
    }
    final res = await _apiClient.get(_u('/api/messages/$convId', q), headers: {'Content-Type': 'application/json'});
    print('📡 [API] Get messages response: ${res.statusCode}');
    if (res.statusCode != 200) throw Exception('Failed messages');
    final arr = jsonDecode(res.body) as List;
    final msgs = arr.map((e) => ChatMessage.fromJson(e as Map<String, dynamic>)).toList();
    msgs.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return msgs;
  }

  Future<ChatMessage> deleteMessage(String messageId) async {
    final res = await _apiClient.delete(
      _u('/api/messages/$messageId'),
      headers: {'Content-Type': 'application/json'},
    );

    print('📡 [API] Delete message response: ${res.statusCode}');
    final data = res.body.isNotEmpty ? jsonDecode(res.body) : null;
    if (res.statusCode != 200) {
      if (data is Map && data['error'] != null) throw Exception(data['error']);
      throw Exception('Delete message failed');
    }
    return ChatMessage.fromJson(data as Map<String, dynamic>);
  }

  Future<void> postPublicKey(String publicKey) async {
    final res = await _apiClient.post(
      _u('/api/keys'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'publicKey': publicKey}),
    );
    print('📡 [API] Post public key response: ${res.statusCode}');
  }

  Future<String?> getPeerPublicKey(String peerUserId) async {
    final res = await _apiClient.get(_u('/api/keys/$peerUserId'), headers: {'Content-Type': 'application/json'});
    print('📡 [API] Get peer public key response: ${res.statusCode}');
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body);
    if (data is Map && data['publicKey'] != null) return data['publicKey'].toString();
    return null;
  }

  Future<String> uploadFile(List<int> bytes, String filename) async {
    final uri = _u('/api/upload');
    // For multipart, we need to pass a BaseRequest through ApiClient
    final req = http.MultipartRequest('POST', uri);
    // ApiClient will automatically add Authorization header

    final mimeType = lookupMimeType(filename) ?? 'application/octet-stream';
    final parts = mimeType.split('/');
    final mt = MediaType(parts[0], parts.length > 1 ? parts[1] : 'octet-stream');

    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename, contentType: mt));

    final streamed = await _apiClient.send(req);
    print('📡 [API] Upload file response: ${streamed.statusCode}');
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 200) throw Exception('Upload failed');
    final data = jsonDecode(body) as Map<String, dynamic>;
    return (data['url'] ?? '').toString();
  }
}

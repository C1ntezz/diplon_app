import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';

import '../app_config.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/user.dart';

class ApiService {
  final _storage = const FlutterSecureStorage();

  String? token;
  String? userId;
  String? username;
  String? displayName;

  Future<void> loadSession() async {
    token = await _storage.read(key: 'jwt_token');
    userId = await _storage.read(key: 'userId');
    username = await _storage.read(key: 'username');
    displayName = await _storage.read(key: 'displayName');
  }

  Future<void> saveSession({
    required String token,
    required String userId,
    required String username,
    required String displayName,
  }) async {
    this.token = token;
    this.userId = userId;
    this.username = username;
    this.displayName = displayName;

    await _storage.write(key: 'jwt_token', value: token);
    await _storage.write(key: 'userId', value: userId);
    await _storage.write(key: 'username', value: username);
    await _storage.write(key: 'displayName', value: displayName);
  }

  Future<void> logout() async {
    token = null; userId = null; username = null; displayName = null;
    await _storage.deleteAll();
  }

  Map<String, String> _jsonHeaders() => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Uri _u(String path, [Map<String, String>? q]) {
    final url = AppConfig.baseUrl.endsWith('/') 
        ? AppConfig.baseUrl.substring(0, AppConfig.baseUrl.length - 1) 
        : AppConfig.baseUrl;
    final uri = Uri.parse('$url$path').replace(queryParameters: q);
    print('📡 [API] ${new DateTime.now().toIso8601String()} Request: $uri');
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

    final res = await http.post(
      _u('/api/auth/register'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': u,
        'password': password,
        if (displayName != null) 'displayName': displayName,
      }),
    );

    print('📡 [API] Register response: ${res.statusCode}');
    final body = res.body.isNotEmpty ? jsonDecode(res.body) : null;
    if (res.statusCode != 200 && res.statusCode != 201) {
      if (body is Map && body['error'] != null) throw Exception(body['error']);
      throw Exception('Register failed');
    }
  }

  Future<List<String>> getOnlineUsers() async {
    final res = await http.get(_u('/api/users/online'), headers: _jsonHeaders());
    print('📡 [API] Online users response: ${res.statusCode}');
    if (res.statusCode != 200) throw Exception('Failed online users');
    final arr = jsonDecode(res.body) as List;
    return arr.map((e) => e.toString()).toList();
  }

  Future<List<AppUser>> getUsers() async {
    final res = await http.get(_u('/api/users'), headers: _jsonHeaders());
    print('📡 [API] Get users response: ${res.statusCode}');
    if (res.statusCode != 200) throw Exception('Failed users');
    final arr = jsonDecode(res.body) as List;
    return arr.map((e) => AppUser.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Conversation>> getConversations() async {
    final res = await http.get(_u('/api/conversations'), headers: _jsonHeaders());
    print('📡 [API] Get conversations response: ${res.statusCode}');
    if (res.statusCode != 200) throw Exception('Failed conversations');
    final arr = jsonDecode(res.body) as List;
    return arr.map((e) => Conversation.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Conversation> createConversation(String otherUserId) async {
    final res = await http.post(
      _u('/api/conversations'),
      headers: _jsonHeaders(),
      body: jsonEncode({'participantIds': [otherUserId]}),
    );
    print('📡 [API] Create conversation response: ${res.statusCode}');
    final data = jsonDecode(res.body);
    if (res.statusCode != 200 && res.statusCode != 201) throw Exception('Create conversation failed');
    return Conversation.fromJson(data as Map<String, dynamic>);
  }

  Future<List<ChatMessage>> getMessages(String convId, {int limit = 50, String? before}) async {
    final q = <String, String>{'limit': limit.toString(), if (before != null) 'before': before};
    final res = await http.get(_u('/api/messages/$convId', q), headers: _jsonHeaders());
    print('📡 [API] Get messages response: ${res.statusCode}');
    if (res.statusCode != 200) throw Exception('Failed messages');
    final arr = jsonDecode(res.body) as List;
    final msgs = arr.map((e) => ChatMessage.fromJson(e as Map<String, dynamic>)).toList();
    msgs.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return msgs;
  }

  Future<void> postPublicKey(String publicKey) async {
    final res = await http.post(
      _u('/api/keys'),
      headers: _jsonHeaders(),
      body: jsonEncode({'publicKey': publicKey}),
    );
    print('📡 [API] Post public key response: ${res.statusCode}');
  }

  Future<String?> getPeerPublicKey(String peerUserId) async {
    final res = await http.get(_u('/api/keys/$peerUserId'), headers: _jsonHeaders());
    print('📡 [API] Get peer public key response: ${res.statusCode}');
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body);
    if (data is Map && data['publicKey'] != null) return data['publicKey'].toString();
    return null;
  }

  Future<String> uploadFile(List<int> bytes, String filename) async {
    final uri = _u('/api/upload');
    final req = http.MultipartRequest('POST', uri);
    req.headers['Authorization'] = 'Bearer $token';

    final mimeType = lookupMimeType(filename) ?? 'application/octet-stream';
    final parts = mimeType.split('/');
    final mt = MediaType(parts[0], parts.length > 1 ? parts[1] : 'octet-stream');

    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename, contentType: mt));

    final streamed = await req.send();
    print('📡 [API] Upload file response: ${streamed.statusCode}');
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 200) throw Exception('Upload failed');
    final data = jsonDecode(body) as Map<String, dynamic>;
    return (data['url'] ?? '').toString();
  }
}

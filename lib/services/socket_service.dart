import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../app_config.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_client.dart';

class SocketService {
  IO.Socket? _socket;
  final _storage = const FlutterSecureStorage();
  final _apiClient = ApiClient();

  IO.Socket get socket => _socket!;

  void connect({required String token}) {
    _socket?.disconnect();
    
    print('🔌 [Socket] Connecting with token...');

    _socket = IO.io(
      AppConfig.socketUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .setAuth({'token': token})
          .build(),
    );

    _socket!.onConnect((_) {
      print('🔌 [Socket] Connected: ${_socket!.id}');
    });

    _socket!.onDisconnect((reason) {
      print('🔌 [Socket] Disconnected: $reason');
    });

    _socket!.onConnectError((err) async {
      print('🔌 [Socket] Connection Error: $err');
      if (err.toString().contains('Authentication error') || err.toString().contains('401')) {
        print('⚠️ [Socket] Ошибка авторизации. Обновляем токен...');
        bool refreshed = await _apiClient.refreshToken();
        if (refreshed) {
           String? newToken = await _storage.read(key: 'accessToken');
           if (newToken != null && _socket != null) {
              _socket!.auth = {'token': newToken};
              _socket!.connect();
           }
        }
      }
    });

    _socket!.connect();
  }

  void disconnect() {
    _socket?.disconnect();
    _socket = null;
  }
}

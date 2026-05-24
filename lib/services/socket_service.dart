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
    
    print('🔌 [Socket] Creating socket (listeners first, connect later)...');

    final opts = IO.OptionBuilder()
        .setTransports(['websocket'])
        .setAuth({'token': token})
        .build();
    opts['autoConnect'] = false;  // Явно запрещаем — подключимся после _bindSocket()

    _socket = IO.io(
      AppConfig.socketUrl,
      opts,
    );

    _socket!.on('connect', (_) {
      print('🔌 [Socket] Connected: ${_socket!.id}');
    });

    _socket!.on('disconnect', (reason) {
      print('🔌 [Socket] Disconnected: $reason');
    });

    _socket!.on('connect_error', (err) async {
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

    // НЕ вызываем _socket!.connect() здесь — соединение запустится после того,
    // как ChatStore привяжет все обработчики через _bindSocket()
  }

  /// Запускает подключение сокета (должен вызываться ПОСЛЕ ChatStore.init/_bindSocket)
  void activateConnection() {
    if (_socket == null) {
      print('❌ [Socket] activateConnection: _socket is NULL — connect() was never called!');
      return;
    }
    print('🔌 [Socket] Activating connection...');
    _socket!.connect();
  }

  void disconnect() {
    _socket?.disconnect();
    _socket = null;
  }
}

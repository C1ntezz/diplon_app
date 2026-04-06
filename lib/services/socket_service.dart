import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../app_config.dart';

class SocketService {
  IO.Socket? _socket;

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

    _socket!.onConnectError((err) {
      print('🔌 [Socket] Connection Error: $err');
    });

    _socket!.connect();
  }

  void disconnect() {
    _socket?.disconnect();
    _socket = null;
  }
}

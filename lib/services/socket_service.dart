import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../app_config.dart';

class SocketService {
  IO.Socket? _socket;

  IO.Socket get socket => _socket!;

  void connect({required String token}) {
    _socket?.disconnect();

    _socket = IO.io(
      AppConfig.socketUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .setAuth({'token': token})
          .build(),
    );

    _socket!.connect();
  }

  void disconnect() {
    _socket?.disconnect();
    _socket = null;
  }
}

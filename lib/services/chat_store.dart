import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import 'api_service.dart';
import 'socket_service.dart';

class ChatStore extends ChangeNotifier {
  final ApiService api;
  final SocketService socketService;

  ChatStore({required this.api, required this.socketService});

  List<Conversation> conversations = [];
  List<ChatMessage> messages = [];
  Set<String> onlineUsers = {};
  String? activeConversationId;
  String? typingText;

  String? oldestTimestamp;
  bool loadingMore = false;

  Timer? _typingHideTimer;

  Future<void> init() async {
    onlineUsers = (await api.getOnlineUsers()).toSet();
    await loadConversations();
    _bindSocket();
  }

  void _bindSocket() {
    final s = socketService.socket;

    s.on('newMessage', (data) {
      final msg = ChatMessage.fromJson(Map<String, dynamic>.from(data));
      if (msg.conversationId == activeConversationId) {
        messages.add(msg);
        messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        notifyListeners();

        if (msg.senderId() != api.userId) {
          if (msg.status == 'sent') s.emit('messageDelivered', msg.id);
          if (msg.status != 'read') s.emit('messageRead', msg.id);
        }
      }
      loadConversations();
    });

    s.on('userOnline', (uid) {
      onlineUsers.add(uid.toString());
      notifyListeners();
    });

    s.on('userOffline', (uid) {
      onlineUsers.remove(uid.toString());
      notifyListeners();
    });

    s.on('messageStatusUpdate', (data) {
      final m = Map<String, dynamic>.from(data);
      final messageId = m['messageId']?.toString();
      final status = m['status']?.toString();
      if (messageId == null || status == null) return;

      final idx = messages.indexWhere((x) => x.id == messageId);
      if (idx != -1) {
        final old = messages[idx];
        messages[idx] = ChatMessage(
          id: old.id,
          conversationId: old.conversationId,
          sender: old.sender,
          content: old.content,
          type: old.type,
          mediaUrl: old.mediaUrl,
          status: status,
          timestamp: old.timestamp,
        );
        notifyListeners();
      }
    });

    s.on('typing', (data) {
      final m = Map<String, dynamic>.from(data);
      final convId = m['conversationId']?.toString();
      final userId = m['userId']?.toString();
      final username = m['username']?.toString() ?? 'User';

      if (convId == activeConversationId && userId != api.userId) {
        typingText = '@ печатает...';
        notifyListeners();

        _typingHideTimer?.cancel();
        _typingHideTimer = Timer(const Duration(milliseconds: 2500), () {
          typingText = null;
          notifyListeners();
        });
      }
    });
  }

  Future<void> loadConversations() async {
    conversations = await api.getConversations();
    notifyListeners();
  }

  Future<void> openConversation(String convId) async {
    activeConversationId = convId;
    messages = await api.getMessages(convId, limit: 50);
    oldestTimestamp = messages.isNotEmpty ? messages.first.timestamp.toIso8601String() : null;
    typingText = null;
    notifyListeners();
  }

  Future<void> loadMore() async {
    if (activeConversationId == null || oldestTimestamp == null || loadingMore) return;
    loadingMore = true;
    notifyListeners();

    try {
      final older = await api.getMessages(activeConversationId!, limit: 50, before: oldestTimestamp);
      if (older.isEmpty) {
        oldestTimestamp = null;
      } else {
        oldestTimestamp = older.first.timestamp.toIso8601String();
        messages = [...older, ...messages];
        messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      }
    } finally {
      loadingMore = false;
      notifyListeners();
    }
  }

  void emitTyping() {
    if (activeConversationId == null) return;
    socketService.socket.emit('typing', {'conversationId': activeConversationId});
  }

  void sendText(String text, {String type = 'text', String? mediaUrl}) {
    if (activeConversationId == null) return;
    socketService.socket.emit('sendMessage', {
      'conversationId': activeConversationId,
      'content': text,
      'type': type,
      'mediaUrl': mediaUrl,
    });
  }
}

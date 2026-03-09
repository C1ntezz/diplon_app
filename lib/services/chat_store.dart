import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/user.dart';
import 'api_service.dart';
import 'socket_service.dart';
import 'encryption_service.dart';

class ChatStore extends ChangeNotifier {
  final ApiService api;
  final SocketService socketService;
  final EncryptionService encryption;

  ChatStore({required this.api, required this.socketService, required this.encryption});

  List<Conversation> conversations = [];
  List<ChatMessage> messages = [];
  Set<String> onlineUsers = {};
  String? activeConversationId;
  String? typingText;

  String? oldestTimestamp;
  bool loadingMore = false;

  Timer? _typingHideTimer;

  Future<void> init() async {
    await encryption.init(api);
    onlineUsers = (await api.getOnlineUsers()).toSet();
    await loadConversations();
    _bindSocket();
  }

  void _bindSocket() {
    final s = socketService.socket;

    s.on('newMessage', (data) async {
      var msg = ChatMessage.fromJson(Map<String, dynamic>.from(data));
      msg = await _decryptIfNeeded(msg);
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
          encryptedPayload: old.encryptedPayload,
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
    final raw = await api.getMessages(convId, limit: 50);
    messages = await _decryptMessages(raw);
    oldestTimestamp = messages.isNotEmpty ? messages.first.timestamp.toIso8601String() : null;
    typingText = null;
    notifyListeners();
  }

  Future<void> loadMore() async {
    if (activeConversationId == null || oldestTimestamp == null || loadingMore) return;
    loadingMore = true;
    notifyListeners();

    try {
      final olderRaw = await api.getMessages(activeConversationId!, limit: 50, before: oldestTimestamp);
      if (olderRaw.isEmpty) {
        oldestTimestamp = null;
      } else {
        final older = await _decryptMessages(olderRaw);
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

  Future<void> sendText(String text, {String type = 'text', String? mediaUrl}) async {
    if (activeConversationId == null) return;

    var payload = text;
    var senderPayload = text; // То, что отправим зашифрованным для себя

    if (text.isNotEmpty && type == 'text') {
      final peerId = await _getPeerUserId();
      if (peerId != null) {
        // 1. Шифруем для собеседника (чужим ключом)
        final peerKey = await api.getPeerPublicKey(peerId);
        if (peerKey != null) {
          final encrypted = await encryption.encryptForPeer(text, peerKey);
          if (encrypted != null) {
            payload = encrypted;
          }
        }

        // 2. Шифруем для себя (своим публичным ключом)
        final myKey = encryption.publicKeySerialized;
        if (myKey != null) {
           final encryptedSelf = await encryption.encryptForPeer(text, myKey);
           if (encryptedSelf != null) {
              senderPayload = encryptedSelf;
           }
        }
      }
    }

    socketService.socket.emit('sendMessage', {
      'conversationId': activeConversationId,
      'content': payload,
      'senderContent': senderPayload,
      'type': type,
      'mediaUrl': mediaUrl,
    });
  }

  Future<String?> _getPeerUserId() async {
    if (activeConversationId == null) return null;
    Conversation? conv = conversations.firstWhere(
      (c) => c.id == activeConversationId,
      orElse: () => Conversation(id: '', type: 'direct', participants: const <AppUser>[]),
    );

    if (conv.id.isEmpty) {
      try {
        conversations = await api.getConversations();
        conv = conversations.firstWhere(
          (c) => c.id == activeConversationId,
          orElse: () => Conversation(id: '', type: 'direct', participants: const <AppUser>[]),
        );
      } catch (_) {
        return null;
      }
    }

    if (conv.id.isEmpty) return null;
    if (conv.type != 'direct' || conv.participants.length < 2) return null;

    final other = conv.participants.firstWhere(
      (p) => p.id != api.userId,
      orElse: () => throw Exception('Other participant not found'),
    );
    return other.id;
  }

  Future<List<ChatMessage>> _decryptMessages(List<ChatMessage> list) async {
    final result = <ChatMessage>[];
    for (final msg in list) {
      result.add(await _decryptIfNeeded(msg));
    }
    return result;
  }

  Future<ChatMessage> _decryptIfNeeded(ChatMessage msg) async {
    // Определяем, моё ли это сообщение
    final isMyMessage = msg.senderId() == api.userId;
    
    // Если это моё сообщение - расшифровываем senderContent (зашифровано для себя)
    // Если чужое - расшифровываем content (зашифровано для меня собеседником)
    final payloadToDecrypt = isMyMessage ? msg.senderContent : msg.content;
    
    if (payloadToDecrypt == null || payloadToDecrypt.isEmpty) return msg;

    final decrypted = await encryption.decryptMessage(payloadToDecrypt);
    if (decrypted == null) return msg;

    return msg.copyWith(
      content: decrypted,
      encryptedPayload: msg.encryptedPayload ?? payloadToDecrypt,
    );
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/conversation.dart';
import '../models/message.dart';
import '../models/user.dart';
import 'api_service.dart';
import 'encryption_service.dart';
import 'socket_service.dart';
import 'notification_service.dart';

class ChatStore extends ChangeNotifier {
  final ApiService api;
  final SocketService socketService;
  final EncryptionService encryption;

  ChatStore({
    required this.api,
    required this.socketService,
    required this.encryption,
  });

  List<Conversation> conversations = [];
  List<ChatMessage> messages = [];
  Set<String> onlineUsers = {};
  Set<String> pinnedConversationIds = {};
  String? activeConversationId;
  String? typingText;
  ChatMessage? replyingTo;

  String? oldestTimestamp;
  bool loadingMore = false;

  Timer? _typingHideTimer;

  Conversation? get activeConversation {
    final convId = activeConversationId;
    if (convId == null) return null;
    try {
      return conversations.firstWhere((c) => c.id == convId);
    } catch (_) {
      return null;
    }
  }

  Future<KeyStatus> init() async {
    final keyStatus = await encryption.init(api);
    onlineUsers = (await api.getOnlineUsers()).toSet();
    await loadConversations();
    _bindSocket();
    return keyStatus;
  }

  void _bindSocket() {
    final s = socketService.socket;

    s.on('newMessage', (data) async {
      var msg = ChatMessage.fromJson(Map<String, dynamic>.from(data));
      msg = await _decryptIfNeeded(msg);
      
      if (msg.conversationId == activeConversationId) {
        // Мы сейчас внутри этого чата, просто добавляем сообщение
        messages.add(msg);
        messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        notifyListeners();

        if (msg.senderId() != api.userId) {
          if (msg.status == 'sent') s.emit('messageDelivered', msg.id);
          if (!msg.readBy.contains(api.userId)) s.emit('messageRead', msg.id);
        }
      } else {
        // Сообщение из ДРУГОГО чата. Показываем локальный Push!
        if (msg.senderId() != api.userId) {
          final senderName = msg.senderAsUser()?.title ?? 'Новое сообщение';
          final text = msg.content ?? (msg.type == 'image' ? '📷 Изображение' : 'Файл');
          await NotificationService().showNewMessageNotification(senderName, text);
          
          if (msg.status == 'sent') s.emit('messageDelivered', msg.id);
        }
      }
      
      // Обновляем список чатов (чтобы обновилось последнее сообщение и сортировка)
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
      final readBy = (m['readBy'] as List? ?? []).map((e) => e.toString()).toList();
      if (messageId == null || status == null) return;

      final idx = messages.indexWhere((x) => x.id == messageId);
      if (idx != -1) {
        final old = messages[idx];
        messages[idx] = old.copyWith(
          status: status,
          readBy: readBy.isEmpty ? old.readBy : readBy,
        );
        notifyListeners();
      }
    });

    s.on('messageDeleted', (data) async {
      final deleted = await _decryptIfNeeded(
        ChatMessage.fromJson(Map<String, dynamic>.from(data)),
      );
      _replaceMessage(deleted);
      _replaceLastMessage(deleted);
      if (replyingTo?.id == deleted.id) {
        replyingTo = null;
      }
      notifyListeners();
    });

    s.on('conversationRead', (data) {
      final m = Map<String, dynamic>.from(data);
      final conversationId = m['conversationId']?.toString();
      final userId = m['userId']?.toString();
      if (conversationId == null || userId == null) return;

      if (conversationId == activeConversationId) {
        messages = messages.map((message) {
          if (message.senderId() == userId || message.readBy.contains(userId)) {
            return message;
          }
          return message.copyWith(readBy: [...message.readBy, userId]);
        }).toList();
      }

      if (userId == api.userId) {
        _markConversationReadLocally(conversationId, notify: false);
      }

      notifyListeners();
    });

    s.on('conversationUpdated', (data) async {
      final updated = Conversation.fromJson(Map<String, dynamic>.from(data));
      final index = conversations.indexWhere((c) => c.id == updated.id);
      if (index == -1) {
        conversations.add(updated);
      } else {
        conversations[index] = updated;
      }
      _sortConversations();
      notifyListeners();
    });

    s.on('conversationRemoved', (conversationId) {
      final removedId = conversationId.toString();
      conversations.removeWhere((c) => c.id == removedId);
      if (activeConversationId == removedId) {
        activeConversationId = null;
        messages = [];
        oldestTimestamp = null;
        replyingTo = null;
      }
      notifyListeners();
    });

    s.on('typing', (data) {
      final m = Map<String, dynamic>.from(data);
      final convId = m['conversationId']?.toString();
      final userId = m['userId']?.toString();

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
    
    // Расшифровываем последнее сообщение для списка чатов
    for (var i = 0; i < conversations.length; i++) {
      if (conversations[i].lastMessage != null) {
        conversations[i].lastMessage = await _decryptIfNeeded(conversations[i].lastMessage!);
      }
    }
    
    _sortConversations();
    notifyListeners();
  }

  Future<Conversation> createGroup({
    required String name,
    required List<String> participantIds,
  }) async {
    final group = await api.createGroupConversation(
      name: name,
      participantIds: participantIds,
    );
    await loadConversations();
    return group;
  }

  Future<void> renameGroup(String conversationId, String name) async {
    final updated = await api.updateGroupName(
      conversationId: conversationId,
      name: name,
    );
    _replaceConversation(updated);
  }

  Future<void> updateGroupMemberRole(String conversationId, String userId, String role) async {
    final updated = await api.updateGroupMemberRole(
      conversationId: conversationId,
      targetUserId: userId,
      role: role,
    );
    _replaceConversation(updated);
  }

  Future<void> addGroupMember(String conversationId, String userId) async {
    final updated = await api.addGroupMember(
      conversationId: conversationId,
      userId: userId,
    );
    _replaceConversation(updated);
  }

  Future<void> removeGroupMember(String conversationId, String userId) async {
    final updated = await api.removeGroupMember(
      conversationId: conversationId,
      userId: userId,
    );
    _replaceConversation(updated);
  }

  Future<void> leaveGroup(String conversationId) async {
    await api.leaveGroup(conversationId: conversationId);
    conversations.removeWhere((c) => c.id == conversationId);
    if (activeConversationId == conversationId) {
      activeConversationId = null;
      messages = [];
      oldestTimestamp = null;
      replyingTo = null;
    }
    notifyListeners();
  }

  bool isConversationPinned(String conversationId) {
    return pinnedConversationIds.contains(conversationId);
  }

  void toggleConversationPinned(String conversationId) {
    if (pinnedConversationIds.contains(conversationId)) {
      pinnedConversationIds.remove(conversationId);
    } else {
      pinnedConversationIds.add(conversationId);
    }

    _sortConversations();
    notifyListeners();
  }

  Future<void> openConversation(String convId) async {
    activeConversationId = convId;
    final raw = await api.getMessages(convId, limit: 50);
    messages = await _decryptMessages(raw);
    oldestTimestamp = messages.isNotEmpty ? messages.first.timestamp.toIso8601String() : null;
    typingText = null;
    replyingTo = null;
    _markConversationReadLocally(convId, notify: false);
    notifyListeners();

    try {
      await api.markConversationRead(convId);
    } catch (e) {
      debugPrint('Ошибка отметки сообщений прочитанными: $e');
    }
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

  void startReply(ChatMessage message) {
    if (message.isDeleted || message.type == 'system') return;
    replyingTo = message;
    notifyListeners();
  }

  void cancelReply() {
    replyingTo = null;
    notifyListeners();
  }

  Future<void> deleteMessage(ChatMessage message) async {
    final deleted = await api.deleteMessage(message.id);
    _replaceMessage(await _decryptIfNeeded(deleted));
    _replaceLastMessage(deleted);
    if (replyingTo?.id == message.id) {
      replyingTo = null;
    }
    notifyListeners();
  }

  Future<void> sendText(String text, {String type = 'text', String? mediaUrl}) async {
    if (activeConversationId == null) return;

    var payload = text;
    var senderPayload = text;

    if (text.isNotEmpty && type == 'text') {
      final peerId = await _getPeerUserId();
      if (peerId != null) {
        final peerKey = await api.getPeerPublicKey(peerId);
        if (peerKey != null) {
          final encrypted = await encryption.encryptForPeer(text, peerKey);
          if (encrypted != null) {
            payload = encrypted;
          }
        }

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
      'replyTo': replyingTo?.id,
    });
    replyingTo = null;
    notifyListeners();
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
        _sortConversations();
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
    final isMyMessage = msg.senderId() == api.userId;
    final payloadToDecrypt = isMyMessage ? msg.senderContent : msg.content;

    final decryptedReply = msg.replyTo == null ? null : await _decryptIfNeeded(msg.replyTo!);

    if (payloadToDecrypt == null || payloadToDecrypt.isEmpty) {
      return decryptedReply == null ? msg : msg.copyWith(replyTo: decryptedReply);
    }

    final decrypted = await encryption.decryptMessage(payloadToDecrypt);
    if (decrypted == null) {
      return decryptedReply == null ? msg : msg.copyWith(replyTo: decryptedReply);
    }

    return msg.copyWith(
      content: decrypted,
      encryptedPayload: msg.encryptedPayload ?? payloadToDecrypt,
      replyTo: decryptedReply,
    );
  }

  void _sortConversations() {
    conversations.sort((a, b) {
      final aPinned = pinnedConversationIds.contains(a.id);
      final bPinned = pinnedConversationIds.contains(b.id);

      if (aPinned != bPinned) {
        return aPinned ? -1 : 1;
      }
      
      // Сортировка по времени последнего обновления (updatedAt)
      final aTime = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });
  }

  void _replaceConversation(Conversation updated) {
    final index = conversations.indexWhere((c) => c.id == updated.id);
    if (index == -1) {
      conversations.add(updated);
    } else {
      conversations[index] = updated;
    }
    _sortConversations();
    notifyListeners();
  }

  void _replaceMessage(ChatMessage updated) {
    final index = messages.indexWhere((m) => m.id == updated.id);
    if (index == -1) return;
    messages[index] = updated;
  }

  void _replaceLastMessage(ChatMessage updated) {
    final index = conversations.indexWhere((c) => c.lastMessage?.id == updated.id);
    if (index == -1) return;
    conversations[index] = conversations[index].copyWith(lastMessage: updated);
  }

  void _markConversationReadLocally(String conversationId, {bool notify = true}) {
    final index = conversations.indexWhere((c) => c.id == conversationId);
    if (index == -1) return;

    conversations[index] = conversations[index].copyWith(unreadCount: 0);

    if (notify) {
      notifyListeners();
    }
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';
import '../utils/turkish_datetime.dart';
import '../widgets/role_icon.dart';
import '../widgets/tag_request_picker.dart';
import '../widgets/user_avatar.dart';
import 'request_detail_screen.dart';

const Map<String, String> _dmRoleLabels = {
  'personel': 'Personel',
  'mudur': 'Müdür',
  'admin': 'Admin',
};

/// Faz 7 (2026-07-23) — bir DM konuşmasının kendisi (mesaj listesi + yazma
/// alanı). `otherFullName`/`otherRole`/`otherAvatarPath` verilmezse (ör. bir
/// bildirime tıklanarak buraya gelinmişse) ekran bunları kendisi
/// `get_my_dm_conversations()`'tan bulur — yeni bir RPC'ye gerek kalmadan,
/// zaten var olan konuşma listesi RPC'sinin yeniden kullanılmasıyla.
///
/// Gerçek zamanlı güncelleme (Supabase Realtime) BİLİNÇLİ olarak
/// kullanılmadı — bu proje hiçbir ekranda Realtime altyapısı kurmamış
/// (bkz. CLAUDE.md), yeni bir altyapı riski eklemek yerine, projedeki
/// "debounce'lu periyodik" desenle (request_filters.dart) tutarlı, basit bir
/// `Timer.periodic` (4 saniyede bir, sadece ekran açıkken) ile "neredeyse
/// canlı" bir deneyim sağlanıyor.
class DmChatScreen extends StatefulWidget {
  const DmChatScreen({
    super.key,
    required this.conversationId,
    this.otherFullName,
    this.otherRole,
    this.otherAvatarPath,
  });

  final String conversationId;
  final String? otherFullName;
  final String? otherRole;
  final String? otherAvatarPath;

  @override
  State<DmChatScreen> createState() => _DmChatScreenState();
}

class _DmChatScreenState extends State<DmChatScreen> {
  static SupabaseClient get _client => SupabaseService.client;
  static const _pollInterval = Duration(seconds: 4);

  final _bodyController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _pollTimer;

  String? _otherFullName;
  String? _otherRole;
  String? _otherAvatarPath;
  bool _isLoadingHeader = false;

  List<Map<String, dynamic>> _messages = [];
  final Map<String, Set<String>> _likesByMessage = {};
  final Map<String, String> _taggedRequestTitles = {};
  bool _isLoadingMessages = true;
  bool _isSending = false;
  Map<String, dynamic>? _taggedRequest;

  String get _myId => _client.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _otherFullName = widget.otherFullName;
    _otherRole = widget.otherRole;
    _otherAvatarPath = widget.otherAvatarPath;
    if (_otherFullName == null) _loadHeaderInfo();
    _markRead();
    _loadMessages(scrollToBottom: true);
    _pollTimer = Timer.periodic(_pollInterval, (_) => _loadMessages());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _bodyController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Bildirimden gelindiğinde karşı tarafın bilgisi bilinmiyor —
  /// `get_my_dm_conversations()` üzerinden bulunuyor (ayrı bir RPC'ye gerek
  /// kalmadan).
  Future<void> _loadHeaderInfo() async {
    setState(() => _isLoadingHeader = true);
    try {
      final rows = await _client.rpc('get_my_dm_conversations') as List;
      final match = rows.cast<Map<String, dynamic>>().firstWhere(
            (row) => row['conversation_id'] == widget.conversationId,
            orElse: () => <String, dynamic>{},
          );
      if (!mounted || match.isEmpty) return;
      setState(() {
        _otherFullName = match['other_full_name'] as String?;
        _otherRole = match['other_role'] as String?;
        _otherAvatarPath = match['other_avatar_url'] as String?;
      });
    } catch (_) {
      // Sessizce yutulur — AppBar başlığı bulunamadan boş kalır.
    } finally {
      if (mounted) setState(() => _isLoadingHeader = false);
    }
  }

  Future<void> _markRead() async {
    try {
      await _client.rpc('mark_dm_conversation_read', params: {
        'p_conversation_id': widget.conversationId,
      });
    } catch (_) {
      // Sessizce yutulur — okundu sayacı ikincil bir bilgi.
    }
  }

  Future<void> _loadMessages({bool scrollToBottom = false}) async {
    try {
      final rows = await _client
          .from('dm_messages')
          .select('id, sender_id, body, tagged_request_id, created_at')
          .eq('conversation_id', widget.conversationId)
          .order('created_at');
      final messages = List<Map<String, dynamic>>.from(rows);

      final ids = messages.map((m) => m['id'] as String).toList();
      if (ids.isNotEmpty) {
        final likeRows = await _client
            .from('dm_message_likes')
            .select('message_id, user_id')
            .inFilter('message_id', ids);
        _likesByMessage.clear();
        for (final row in List<Map<String, dynamic>>.from(likeRows)) {
          final messageId = row['message_id'] as String;
          _likesByMessage.putIfAbsent(messageId, () => {}).add(row['user_id'] as String);
        }
      }

      final taggedIds = messages
          .map((m) => m['tagged_request_id'] as String?)
          .whereType<String>()
          .where((id) => !_taggedRequestTitles.containsKey(id))
          .toSet()
          .toList();
      if (taggedIds.isNotEmpty) {
        try {
          final requestRows = await _client
              .from('requests')
              .select('id, title')
              .inFilter('id', taggedIds);
          for (final row in List<Map<String, dynamic>>.from(requestRows)) {
            _taggedRequestTitles[row['id'] as String] = row['title'] as String? ?? 'Talep';
          }
        } catch (_) {
          // Sessizce yutulur — bulunamayan etiketler "Erişilemeyen talep" gösterir.
        }
      }

      if (!mounted) return;
      setState(() => _messages = messages);
      if (scrollToBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    } catch (_) {
      // Sessizce yutulur — bir sonraki periyodik yenilemede tekrar denenir.
    } finally {
      if (mounted && _isLoadingMessages) setState(() => _isLoadingMessages = false);
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _pickTaggedRequest() async {
    final selected = await showTagRequestPicker(context);
    if (selected == null || !mounted) return;
    setState(() => _taggedRequest = selected);
  }

  Future<void> _send() async {
    final text = _bodyController.text.trim();
    final tagged = _taggedRequest;
    if (text.isEmpty && tagged == null) return;

    final body = text.isNotEmpty ? text : 'Talep: ${tagged!['title']}';

    setState(() => _isSending = true);
    try {
      await _client.from('dm_messages').insert({
        'conversation_id': widget.conversationId,
        'sender_id': _myId,
        'body': body,
        'tagged_request_id': tagged?['id'],
      });
      if (!mounted) return;
      _bodyController.clear();
      setState(() => _taggedRequest = null);
      await _loadMessages(scrollToBottom: true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mesaj gönderilemedi. Lütfen tekrar deneyin.')),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _toggleLike(String messageId) async {
    final likedByMe = _likesByMessage[messageId]?.contains(_myId) ?? false;
    setState(() {
      final likers = _likesByMessage.putIfAbsent(messageId, () => {});
      if (likedByMe) {
        likers.remove(_myId);
      } else {
        likers.add(_myId);
      }
    });
    try {
      if (likedByMe) {
        await _client
            .from('dm_message_likes')
            .delete()
            .eq('message_id', messageId)
            .eq('user_id', _myId);
      } else {
        await _client.from('dm_message_likes').insert({'message_id': messageId, 'user_id': _myId});
      }
    } catch (_) {
      // Başarısız olursa bir sonraki periyodik yenileme gerçek durumu düzeltir.
    }
  }

  void _openTaggedRequest(String requestId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RequestDetailScreen(requestId: requestId)),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> message) {
    final isMine = message['sender_id'] == _myId;
    final messageId = message['id'] as String;
    final taggedId = message['tagged_request_id'] as String?;
    final likers = _likesByMessage[messageId] ?? const <String>{};
    final likedByMe = likers.contains(_myId);
    final theme = Theme.of(context);
    final bubbleColor = isMine
        ? theme.colorScheme.primary.withValues(alpha: 0.85)
        : theme.colorScheme.surfaceContainerHighest;
    final textColor = isMine ? Colors.white : theme.colorScheme.onSurface;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        padding: const EdgeInsets.all(10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (taggedId != null) ...[
              InkWell(
                onTap: () => _openTaggedRequest(taggedId),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.attachment, size: 14, color: isMine ? Colors.white : Colors.blue),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        _taggedRequestTitles[taggedId] ?? 'Erişilemeyen talep',
                        style: TextStyle(
                          color: isMine ? Colors.white : Colors.blue,
                          decoration: TextDecoration.underline,
                          decorationColor: isMine ? Colors.white : Colors.blue,
                          fontStyle: FontStyle.italic,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
            ],
            Text(message['body'] as String? ?? '', style: TextStyle(color: textColor)),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formatTurkishRelativeDateTime(message['created_at'] as String?),
                  style: TextStyle(fontSize: 10, color: textColor.withValues(alpha: 0.7)),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: () => _toggleLike(messageId),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        likedByMe ? Icons.favorite : Icons.favorite_border,
                        size: 14,
                        color: likedByMe ? Colors.redAccent : textColor.withValues(alpha: 0.7),
                      ),
                      if (likers.isNotEmpty) ...[
                        const SizedBox(width: 2),
                        Text(
                          '${likers.length}',
                          style: TextStyle(fontSize: 10, color: textColor.withValues(alpha: 0.7)),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            UserAvatar(avatarPath: _otherAvatarPath, fullName: _otherFullName, radius: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _isLoadingHeader ? '...' : (_otherFullName ?? 'Bilinmeyen'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15),
                  ),
                  if (_otherRole != null)
                    Row(
                      children: [
                        Icon(roleIcon(_otherRole!), size: 11),
                        const SizedBox(width: 3),
                        Text(
                          _dmRoleLabels[_otherRole] ?? _otherRole!,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoadingMessages
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? const Center(child: Text('Henüz mesaj yok. İlk mesajı siz gönderin.'))
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) => _buildMessageBubble(_messages[index]),
                      ),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_taggedRequest != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Chip(
                        avatar: const Icon(Icons.attachment, size: 16),
                        label: Text(
                          _taggedRequest!['title'] as String? ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onDeleted: () => setState(() => _taggedRequest = null),
                      ),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.attachment),
                        tooltip: 'Talep Etiketle',
                        onPressed: _isSending ? null : _pickTaggedRequest,
                      ),
                      Expanded(
                        child: TextField(
                          controller: _bodyController,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                          decoration: const InputDecoration(
                            hintText: 'Mesaj yazın...',
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: _isSending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.send),
                        onPressed: _isSending ? null : _send,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

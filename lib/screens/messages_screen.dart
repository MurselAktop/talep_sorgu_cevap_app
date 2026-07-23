import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';
import '../utils/turkish_datetime.dart';
import '../widgets/app_nav_route.dart';
import '../widgets/navigation_shell.dart';
import '../widgets/role_icon.dart';
import '../widgets/user_avatar.dart';
import 'dm_chat_screen.dart';

const Map<String, String> _messagesRoleLabels = {
  'personel': 'Personel',
  'mudur': 'Müdür',
  'admin': 'Admin',
};

/// Faz 7 (2026-07-23) — kurum-içi DM konuşma listesi. Sadece personel/müdür/
/// admin'e görünür (`app_nav_items.dart`'ta `canViewIncoming` ile aynı
/// koşul); vatandaş DM kapsamı dışında (kullanıcı kararı). Konuşma listesi ve
/// "kiminle yeni konuşma başlatabilirim" listesi, `users` tablosunun normal
/// RLS'i bu ilişkileri göremediği için `security definer` RPC'lerden geliyor
/// (bkz. migration'daki gerekçe).
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  static SupabaseClient get _client => SupabaseService.client;

  List<Map<String, dynamic>> _conversations = [];
  bool _isLoading = true;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    setState(() {
      _isLoading = true;
      _errorText = null;
    });
    try {
      final rows = await _client.rpc('get_my_dm_conversations') as List;
      if (!mounted) return;
      setState(() => _conversations = List<Map<String, dynamic>>.from(rows));
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _errorText = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorText = 'Konuşmalar yüklenemedi. Lütfen tekrar deneyin.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openConversation(Map<String, dynamic> conversation) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DmChatScreen(
          conversationId: conversation['conversation_id'] as String,
          otherFullName: conversation['other_full_name'] as String?,
          otherRole: conversation['other_role'] as String?,
          otherAvatarPath: conversation['other_avatar_url'] as String?,
        ),
      ),
    );
    if (mounted) _loadConversations();
  }

  Future<void> _openNewMessageSheet() async {
    final contact = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ContactPickerSheet(),
    );
    if (contact == null || !mounted) return;

    try {
      final conversationId = await _client.rpc(
        'get_or_create_dm_conversation',
        params: {'p_other_user_id': contact['user_id']},
      ) as String;
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DmChatScreen(
            conversationId: conversationId,
            otherFullName: contact['full_name'] as String?,
            otherRole: contact['role'] as String?,
            otherAvatarPath: contact['avatar_url'] as String?,
          ),
        ),
      );
      if (mounted) _loadConversations();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Konuşma başlatılamadı. Lütfen tekrar deneyin.')),
      );
    }
  }

  Widget _buildConversationTile(Map<String, dynamic> conversation) {
    final unreadCount = conversation['unread_count'] as int? ?? 0;
    final isUnread = unreadCount > 0;
    final otherRole = conversation['other_role'] as String?;

    return ListTile(
      leading: UserAvatar(
        avatarPath: conversation['other_avatar_url'] as String?,
        fullName: conversation['other_full_name'] as String?,
        radius: 24,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              conversation['other_full_name'] as String? ?? 'Bilinmeyen',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: isUnread ? FontWeight.bold : FontWeight.normal),
            ),
          ),
          if (otherRole != null) ...[
            const SizedBox(width: 6),
            Icon(roleIcon(otherRole), size: 13, color: Theme.of(context).colorScheme.primary),
          ],
        ],
      ),
      subtitle: Text(
        (conversation['last_message_body'] as String?) ?? 'Henüz mesaj yok',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: isUnread ? FontWeight.w600 : FontWeight.normal),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            formatTurkishRelativeDateTime(conversation['last_message_at'] as String?),
            style: TextStyle(
              fontSize: 11,
              color: isUnread ? Theme.of(context).colorScheme.primary : Colors.grey,
            ),
          ),
          if (isUnread) ...[
            const SizedBox(height: 4),
            Badge(label: Text('$unreadCount')),
          ],
        ],
      ),
      onTap: () => _openConversation(conversation),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_errorText != null) {
      body = Center(child: Text(_errorText!));
    } else if (_conversations.isEmpty) {
      body = const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Henüz bir mesajınız yok.\nYeni bir mesaj başlatmak için sağ alttaki butona dokunun.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _loadConversations,
        child: ListView.separated(
          itemCount: _conversations.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) => _buildConversationTile(_conversations[index]),
        ),
      );
    }

    return NavigationShell(
      currentRoute: AppNavRoute.messages,
      title: 'Mesajlar',
      body: body,
      floatingActionButton: FloatingActionButton(
        onPressed: _openNewMessageSheet,
        tooltip: 'Yeni Mesaj',
        child: const Icon(Icons.add_comment_outlined),
      ),
    );
  }
}

/// "Yeni Mesaj" ile açılan, `get_dm_contacts()`'ın döndürdüğü (role bazlı
/// izinli) kişi listesi.
class _ContactPickerSheet extends StatefulWidget {
  const _ContactPickerSheet();

  @override
  State<_ContactPickerSheet> createState() => _ContactPickerSheetState();
}

class _ContactPickerSheetState extends State<_ContactPickerSheet> {
  static SupabaseClient get _client => SupabaseService.client;

  List<Map<String, dynamic>> _contacts = [];
  bool _isLoading = true;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await _client.rpc('get_dm_contacts') as List;
      if (!mounted) return;
      setState(() => _contacts = List<Map<String, dynamic>>.from(rows));
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorText = 'Kişi listesi yüklenemedi. Lütfen tekrar deneyin.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Yeni Mesaj', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorText != null
                    ? Center(child: Text(_errorText!))
                    : _contacts.isEmpty
                        ? const Center(child: Text('Mesaj gönderebileceğiniz kimse bulunamadı.'))
                        : ListView.builder(
                            controller: scrollController,
                            itemCount: _contacts.length,
                            itemBuilder: (context, index) {
                              final contact = _contacts[index];
                              final role = contact['role'] as String?;
                              return ListTile(
                                leading: UserAvatar(
                                  avatarPath: contact['avatar_url'] as String?,
                                  fullName: contact['full_name'] as String?,
                                  radius: 20,
                                ),
                                title: Text(contact['full_name'] as String? ?? ''),
                                subtitle: role != null ? Text(_messagesRoleLabels[role] ?? role) : null,
                                trailing: role != null ? Icon(roleIcon(role)) : null,
                                onTap: () => Navigator.of(context).pop(contact),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

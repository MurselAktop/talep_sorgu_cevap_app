import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';
import 'request_detail_screen.dart';

const List<String> _turkishMonths = [
  'Ocak',
  'Şubat',
  'Mart',
  'Nisan',
  'Mayıs',
  'Haziran',
  'Temmuz',
  'Ağustos',
  'Eylül',
  'Ekim',
  'Kasım',
  'Aralık',
];

/// `created_at` gibi ISO 8601 zaman damgalarını "gün Ay yıl saat:dakika"
/// biçiminde, Türkçe ay adlarıyla gösterir (intl paketine ihtiyaç duymadan).
String _formatDateTime(String? isoString) {
  if (isoString == null) return '';
  final date = DateTime.tryParse(isoString);
  if (date == null) return isoString;

  final local = date.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = _turkishMonths[local.month - 1];
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day $month ${local.year} $hour:$minute';
}

/// Giriş yapmış kullanıcının kendi bildirimlerini listelediği ekran. RLS
/// (`kendi_bildirimini_gorebilir`) zaten sadece `user_id = auth.uid()` olan
/// satırları döndürdüğü için ek bir istemci tarafı filtre gerekmez (bkz.
/// CLAUDE.md — RLS Planı, notifications).
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static SupabaseClient get _client => SupabaseService.client;

  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    try {
      final response =
          await _client.from('notifications').select().order('created_at', ascending: false);
      setState(() => _notifications = List<Map<String, dynamic>>.from(response));
    } on PostgrestException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bildirimler yüklenemedi. Lütfen tekrar deneyin.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin.')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _onNotificationTap(Map<String, dynamic> notification) async {
    final notificationId = notification['id'] as String;
    final isRead = notification['is_read'] as bool? ?? false;

    if (!isRead) {
      try {
        await _client.from('notifications').update({'is_read': true}).eq('id', notificationId);
        if (mounted) {
          setState(() {
            final index = _notifications.indexWhere((n) => n['id'] == notificationId);
            if (index != -1) _notifications[index]['is_read'] = true;
          });
        }
      } on PostgrestException {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bildirim okundu olarak işaretlenemedi. Lütfen tekrar deneyin.'),
          ),
        );
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin.')),
        );
      }
    }

    final requestId = notification['request_id'] as String?;
    if (requestId == null || !mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RequestDetailScreen(requestId: requestId)),
    );
  }

  Widget _buildNotificationCard(Map<String, dynamic> notification) {
    final isRead = notification['is_read'] as bool? ?? false;
    final message = notification['message'] as String? ?? '';
    final createdAt = notification['created_at'] as String?;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: Icon(Icons.circle, size: 10, color: isRead ? Colors.transparent : Colors.blue),
        title: Text(
          message,
          style: TextStyle(
            fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
            color: isRead ? Colors.grey.shade600 : null,
          ),
        ),
        subtitle: Text(
          _formatDateTime(createdAt),
          style: TextStyle(color: isRead ? Colors.grey.shade500 : null),
        ),
        onTap: () => _onNotificationTap(notification),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bildirimler')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? const Center(child: Text('Hiç bildiriminiz yok.'))
              : ListView.builder(
                  itemCount: _notifications.length,
                  itemBuilder: (context, index) => _buildNotificationCard(_notifications[index]),
                ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';
import '../widgets/app_nav_route.dart';
import '../widgets/navigation_shell.dart';

const Map<String, String> _emailChangeStatusLabels = {
  'beklemede': 'Beklemede',
  'onaylandi': 'Onaylandı',
  'reddedildi': 'Reddedildi',
};

/// Admin'in personel/vatandaş/müdürden gelen e-posta değişikliği taleplerini
/// onayladığı/reddettiği ekran (2026-07-22). Onay/red, doğrudan `users`/
/// `email_change_requests` tablosuna UPDATE ATMAZ — `admin_review_email_change`
/// RPC'si (security definer) üzerinden yapılır; bu fonksiyon aynı zamanda
/// `auth.users.email`'i de günceller (bkz. migration'daki gerekçe: GoTrue'nun
/// kendi "yeni adrese link gönder" akışı burada bilinçli olarak devre dışı,
/// admin onayının kendisi doğrulama sayılıyor).
class AdminEmailChangeRequestsScreen extends StatefulWidget {
  const AdminEmailChangeRequestsScreen({super.key});

  @override
  State<AdminEmailChangeRequestsScreen> createState() => _AdminEmailChangeRequestsScreenState();
}

class _AdminEmailChangeRequestsScreenState extends State<AdminEmailChangeRequestsScreen> {
  static SupabaseClient get _client => SupabaseService.client;

  List<Map<String, dynamic>> _requests = [];
  bool _isLoading = true;
  final Set<String> _processingIds = {};

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    try {
      final response = await _client
          .from('email_change_requests')
          .select('id, current_email, requested_email, status, created_at, users!email_change_requests_user_id_fkey(full_name)')
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() => _requests = List<Map<String, dynamic>>.from(response));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Talepler yüklenemedi. Lütfen sayfayı yenileyin.')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _review(Map<String, dynamic> request, bool approve) async {
    final id = request['id'] as String;
    setState(() => _processingIds.add(id));
    try {
      await _client.rpc(
        'admin_review_email_change',
        params: {'p_request_id': id, 'p_approve': approve},
      );
      await _loadRequests();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(approve ? 'E-posta değişikliği onaylandı.' : 'Talep reddedildi.')),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('İşlem başarısız oldu. Lütfen tekrar deneyin.')),
      );
    } finally {
      if (mounted) setState(() => _processingIds.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return NavigationShell(
      currentRoute: AppNavRoute.emailChangeRequests,
      title: 'E-posta Değişiklik Talepleri',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _requests.isEmpty
              ? const Center(child: Text('Henüz bir e-posta değişikliği talebi yok.'))
              : ListView.builder(
                  itemCount: _requests.length,
                  itemBuilder: (context, index) {
                    final request = _requests[index];
                    final status = request['status'] as String;
                    final isPending = status == 'beklemede';
                    final isProcessing = _processingIds.contains(request['id']);
                    final user = request['users'] as Map<String, dynamic>?;

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?['full_name'] as String? ?? 'Bilinmeyen kullanıcı',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text('Mevcut: ${request['current_email']}'),
                            Text('Yeni: ${request['requested_email']}'),
                            const SizedBox(height: 8),
                            Chip(
                              visualDensity: VisualDensity.compact,
                              label: Text(_emailChangeStatusLabels[status] ?? status),
                            ),
                            if (isPending) ...[
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  FilledButton(
                                    onPressed: isProcessing ? null : () => _review(request, true),
                                    child: const Text('Onayla'),
                                  ),
                                  const SizedBox(width: 12),
                                  OutlinedButton(
                                    onPressed: isProcessing ? null : () => _review(request, false),
                                    child: const Text('Reddet'),
                                  ),
                                  if (isProcessing) ...[
                                    const SizedBox(width: 12),
                                    const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

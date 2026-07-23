import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';
import '../widgets/app_nav_route.dart';
import '../widgets/navigation_shell.dart';
import '../widgets/star_rating.dart';

const Map<String, String> _adminUsersRoleLabels = {
  'vatandas': 'Vatandaş',
  'personel': 'Personel',
  'mudur': 'Müdür',
  'admin': 'Admin',
};

/// Admin'in kullanıcı hesaplarını sil yerine pasifleştirdiği ekran (Faz 4).
/// Pasifleştirme `admin_set_user_active` RPC'si üzerinden yapılır — genel bir
/// "admin herkesi güncelleyebilir" RLS politikası yerine bilinçli olarak dar
/// kapsamlı bir RPC (sadece `is_active` sütununa dokunur, `role`/
/// `department_id` gibi başka alanları REST üzerinden değiştirilebilir hale
/// getirmez). Admin kendi hesabını bu ekrandan pasifleştiremez (RPC de
/// bunu reddeder, buton burada ayrıca gizlenir).
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  static SupabaseClient get _client => SupabaseService.client;

  List<Map<String, dynamic>> _users = [];
  bool _isLoadingUsers = true;
  // Faz 6 (2026-07-23) — personel_id -> {avg_rating, rating_count}. Admin
  // ekranı "personel bilgi sekmesinde hem genel bilgilerini hem başarı
  // oranlarını görsün" isteğiyle eklendi.
  Map<String, Map<String, dynamic>> _ratingsByPersonnelId = {};

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      final response = await _client
          .from('users')
          .select('id, email, full_name, role, is_active, departments(name)')
          .order('full_name');
      setState(() => _users = List<Map<String, dynamic>>.from(response));
      _loadRatings();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kullanıcılar yüklenemedi. Lütfen sayfayı yenileyin.')),
      );
    } finally {
      if (mounted) setState(() => _isLoadingUsers = false);
    }
  }

  /// Puan bilgisi ikincil olduğundan hata sessizce yutulur — liste yine de
  /// yıldızsız gösterilmeye devam eder.
  Future<void> _loadRatings() async {
    try {
      final rows = await _client.rpc('get_personnel_ratings') as List;
      if (!mounted) return;
      setState(() {
        _ratingsByPersonnelId = {
          for (final row in rows) row['personnel_id'] as String: Map<String, dynamic>.from(row),
        };
      });
    } catch (_) {
      // Sessizce yutulur.
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> user) async {
    try {
      await _client.rpc(
        'admin_set_user_active',
        params: {
          'p_user_id': user['id'],
          'p_is_active': !(user['is_active'] as bool),
        },
      );
      await _loadUsers();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Güncellenemedi. Lütfen tekrar deneyin.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _client.auth.currentUser?.id;

    return NavigationShell(
      currentRoute: AppNavRoute.users,
      title: 'Kullanıcı Yönetimi',
      body: _isLoadingUsers
          ? const Center(child: CircularProgressIndicator())
          : _users.isEmpty
              ? const Center(child: Text('Görüntülenecek kullanıcı bulunamadı.'))
              : ListView.builder(
                  itemCount: _users.length,
                  itemBuilder: (context, index) {
                    final user = _users[index];
                    final isActive = user['is_active'] as bool;
                    final role = user['role'] as String;
                    final department = user['departments'] as Map<String, dynamic>?;
                    final isSelf = user['id'] == currentUserId;
                    final ratingInfo = _ratingsByPersonnelId[user['id']];

                    return ListTile(
                      title: Text(user['full_name'] as String? ?? ''),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${user['email']} — ${_adminUsersRoleLabels[role] ?? role}'
                            '${department != null ? ' — ${department['name']}' : ''}',
                          ),
                          if (role == 'personel') ...[
                            const SizedBox(height: 4),
                            StarRatingDisplay(
                              rating: (ratingInfo?['avg_rating'] as num?)?.toDouble(),
                              ratingCount: ratingInfo?['rating_count'] as int?,
                              size: 14,
                            ),
                          ],
                        ],
                      ),
                      isThreeLine: role == 'personel',
                      trailing: isSelf
                          ? const Text('Siz', style: TextStyle(color: Colors.grey))
                          : TextButton(
                              onPressed: () => _toggleActive(user),
                              child: Text(
                                isActive ? 'Pasif Yap' : 'Aktif Yap',
                                style: TextStyle(
                                  color: isActive ? Colors.red : Colors.green,
                                ),
                              ),
                            ),
                    );
                  },
                ),
    );
  }
}

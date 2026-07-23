import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';
import '../widgets/app_nav_route.dart';
import '../widgets/navigation_shell.dart';
import '../widgets/request_filters.dart';
import '../widgets/role_icon.dart';
import '../widgets/stats_dashboard_widgets.dart';
import '../widgets/status_badge.dart';
import '../widgets/user_avatar.dart';
import 'admin_stats_screen.dart';
import 'manager_stats_screen.dart';
import 'my_requests_screen.dart';
import 'profile_screen.dart';
import 'request_create_screen.dart';
import 'request_detail_screen.dart';
import 'request_list_screen.dart';

const Map<String, String> _homeRoleLabels = {
  'vatandas': 'Vatandaş',
  'personel': 'Personel',
  'mudur': 'Müdür',
  'admin': 'Admin',
};

/// Ana Sayfa — karşılama (avatar + rol ikonu), "Hızlı Eylemler" (Talep
/// Oluştur), "Taleplerim"/"Gelen Talepler" özet kartları ve (2026-07-22
/// güncellemesi) birim/son talep detaylarını gösteren ek kartlar. Kendi
/// `Scaffold`/`AppBar`'ını YAZMAZ — sol gezinme menüsü + bildirim zili
/// gibi ortak kabuk artık `NavigationShell`de, tek merkezi yerde.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static SupabaseClient get _client => SupabaseService.client;

  bool _isLoadingRole = true;
  bool _canViewIncoming = false;
  String? _fullName;
  String? _avatarPath;
  String _role = 'vatandas';
  String? _departmentLabel;

  bool _isLoadingCounts = true;
  Map<String, int> _myRequestCounts = {};
  Map<String, int> _incomingRequestCounts = {};

  Map<String, dynamic>? _latestOwnRequest;

  bool _isLoadingMiniStats = false;
  Map<String, int>? _miniStatusTotals;

  @override
  void initState() {
    super.initState();
    _loadRoleAndCounts();
  }

  /// Sonucu ekranda hiçbir şekilde göstermiyoruz (bildirimler zaten
  /// notifications_screen.dart'ta görünür) — sessizce yutulur.
  Future<void> _checkSlaBreaches() async {
    try {
      await _client.rpc('check_sla_breaches');
    } catch (_) {
      // Sessizce yutulur.
    }
  }

  Map<String, int> _countByStatus(List<dynamic> rows) {
    final counts = <String, int>{};
    for (final row in rows) {
      final status = (row as Map<String, dynamic>)['status'] as String? ?? '';
      counts[status] = (counts[status] ?? 0) + 1;
    }
    return counts;
  }

  Future<void> _loadRoleAndCounts() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _isLoadingRole = false);
      return;
    }

    String role = 'vatandas';
    int? departmentId;
    try {
      final profile = await _client
          .from('users')
          .select('role, full_name, department_id, is_active, avatar_url')
          .eq('id', userId)
          .single();

      if (profile['is_active'] == false) {
        // Faz 4 notu: açık bir oturum, hesap admin tarafından pasifleştikten
        // SONRA da devam edebiliyor — burada sessizce sayaçları/rolü
        // yüklemeyi bırakıyoruz, geri kalan güvenlik zaten RLS/RPC'de.
        if (mounted) setState(() => _isLoadingRole = false);
        return;
      }

      role = profile['role'] as String;
      departmentId = profile['department_id'] as int?;
      if (mounted) {
        setState(() {
          _canViewIncoming = role == 'personel' || role == 'mudur' || role == 'admin';
          _fullName = profile['full_name'] as String?;
          _avatarPath = profile['avatar_url'] as String?;
          _role = role;
        });
      }

      if (departmentId != null) {
        _loadDepartmentLabel(departmentId);
      }

      // Faz 5: SLA eskalasyon kontrolü, müdür/admin ana sayfayı her açtığında
      // fire-and-forget tetiklenir (bkz. CLAUDE.md, "uygulama açılışında
      // kontrol" kararı).
      if (role == 'mudur' || role == 'admin') {
        _checkSlaBreaches();
        _loadMiniStats(role);
      }
    } catch (_) {
      // Rol okunamazsa özet kartları gösterilmez; sayfa çalışmaya devam eder.
    } finally {
      if (mounted) setState(() => _isLoadingRole = false);
    }

    await _loadCounts(userId: userId, role: role, departmentId: departmentId);
    await _loadLatestOwnRequest(userId);
  }

  Future<void> _loadDepartmentLabel(int departmentId) async {
    try {
      final department = await _client
          .from('departments')
          .select('name')
          .eq('id', departmentId)
          .single();
      if (mounted) setState(() => _departmentLabel = department['name'] as String?);
    } catch (_) {
      // Sessizce yutulur — birim adı sadece bir detay bilgisi.
    }
  }

  /// Admin/müdür ana sayfasındaki küçük "widget tarzı" dashboard (2026-07-23
  /// isteği) — `admin_stats_screen.dart`/`manager_stats_screen.dart`'ın
  /// kullandığı AYNI RPC'lerden (`get_admin_stats`/`get_manager_stats`) genel
  /// durum toplamlarını çekip özet KPI kartları olarak gösteriyor; detaylı
  /// grafikler için tıklanınca ilgili tam istatistik ekranına gidiliyor.
  Future<void> _loadMiniStats(String role) async {
    setState(() => _isLoadingMiniStats = true);
    try {
      final rows = await _client.rpc(role == 'admin' ? 'get_admin_stats' : 'get_manager_stats');
      final totals = <String, int>{};
      for (final row in (rows as List)) {
        final status = row['status'] as String;
        totals[status] = (totals[status] ?? 0) + (row['request_count'] as int);
      }
      if (mounted) setState(() => _miniStatusTotals = totals);
    } catch (_) {
      // Sessizce yutulur — mini dashboard ikincil bir bilgi.
    } finally {
      if (mounted) setState(() => _isLoadingMiniStats = false);
    }
  }

  /// "Daha çok detay" isteği: kullanıcının en son açtığı kendi talebinin
  /// kısa bir özeti, tıklanınca doğrudan detay ekranına gider.
  Future<void> _loadLatestOwnRequest(String userId) async {
    try {
      final rows = await _client
          .from('requests')
          .select('id, title, status, created_at')
          .eq('created_by', userId)
          .order('created_at', ascending: false)
          .limit(1);
      if (mounted && rows.isNotEmpty) {
        setState(() => _latestOwnRequest = rows.first);
      }
    } catch (_) {
      // Sessizce yutulur.
    }
  }

  /// "Taleplerim" ve (varsa) "Gelen Talepler" özet kartları için durum bazlı
  /// sayımlar. Filtre mantığı, bu listeleri gösteren gerçek ekranlarla
  /// (my_requests_screen.dart / request_list_screen.dart) BİREBİR aynı —
  /// aksi halde özet kartındaki sayı, o karta tıklayınca açılan listeyle
  /// tutarsız görünürdü.
  Future<void> _loadCounts({
    required String userId,
    required String role,
    required int? departmentId,
  }) async {
    try {
      final myRows = await _client.from('requests').select('status').eq('created_by', userId);

      List<dynamic> incomingRows = const [];
      if (role == 'personel') {
        incomingRows = await _client.from('requests').select('status').eq('assigned_to', userId);
      } else if (role == 'mudur' && departmentId != null) {
        incomingRows = await _client
            .from('requests')
            .select('status')
            .eq('department_id', departmentId);
      } else if (role == 'admin') {
        incomingRows = await _client.from('requests').select('status');
      }

      if (!mounted) return;
      setState(() {
        _myRequestCounts = _countByStatus(myRows);
        _incomingRequestCounts = _countByStatus(incomingRows);
      });
    } catch (_) {
      // Özet kartları ikincil bir bilgi — sessizce yutulur, sayfanın geri
      // kalanı (Hızlı Eylemler vb.) çalışmaya devam eder.
    } finally {
      if (mounted) setState(() => _isLoadingCounts = false);
    }
  }

  Widget _buildSummaryCard({
    required String title,
    required Map<String, int> counts,
    required VoidCallback onTap,
  }) {
    final total = counts.values.fold<int>(0, (sum, count) => sum + count);
    const orderedStatuses = ['acik', 'cozuldu', 'onaylandi', 'reddedildi', 'iptal'];
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Talep Özeti',
                  style: TextStyle(fontSize: 12, color: onSurface.withValues(alpha: 0.6)),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const Spacer(),
                    _isLoadingCounts
                        ? const SizedBox(
                            height: 14,
                            width: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            '$total',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
                          ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final status in orderedStatuses)
                      if ((counts[status] ?? 0) > 0)
                        Chip(
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: EdgeInsets.zero,
                          backgroundColor: tonalColors(context, statusColors[status] ?? Colors.grey).background,
                          label: Text(
                            '${statusLabels[status] ?? status}: ${counts[status]}',
                            style: TextStyle(
                              fontSize: 11,
                              color: tonalColors(context, statusColors[status] ?? Colors.grey).foreground,
                            ),
                          ),
                        ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLatestRequestCard() {
    final request = _latestOwnRequest;
    if (request == null) return const SizedBox.shrink();
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Card(
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => RequestDetailScreen(requestId: request['id'] as String)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Son Talebim',
                  style: TextStyle(fontSize: 12, color: onSurface.withValues(alpha: 0.6)),
                ),
                const SizedBox(height: 6),
                Text(
                  request['title'] as String? ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 10),
                StatusBadge(status: request['status'] as String? ?? ''),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMiniStatsDashboard() {
    if (_role != 'admin' && _role != 'mudur') return const SizedBox.shrink();
    final totals = _miniStatusTotals;
    final total = totals?.values.fold<int>(0, (sum, count) => sum + count) ?? 0;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () =>
            _goTo(_role == 'admin' ? const AdminStatsScreen() : const ManagerStatsScreen()),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.insights, color: Colors.pink),
                  const SizedBox(width: 8),
                  const Text(
                    'İstatistikler',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const Spacer(),
                  if (_isLoadingMiniStats)
                    const SizedBox(
                      height: 14,
                      width: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 14),
              if (totals == null || total == 0)
                const Text('Henüz talep bulunmuyor.')
              else
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    KpiCard(label: 'Toplam', value: total, color: Colors.indigo),
                    for (final status in const ['acik', 'cozuldu', 'onaylandi', 'reddedildi'])
                      if ((totals[status] ?? 0) > 0)
                        KpiCard(
                          label: statusLabels[status] ?? status,
                          value: totals[status]!,
                          color: statusColors[status] ?? Colors.grey,
                        ),
                  ],
                ),
              const SizedBox(height: 8),
              Text(
                'Detaylı analiz için dokunun',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _goTo(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final roleLabel = _homeRoleLabels[_role] ?? _role;

    return NavigationShell(
      currentRoute: AppNavRoute.home,
      title: 'Ana Sayfa',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                UserAvatar(
                  avatarPath: _avatarPath,
                  fullName: _fullName,
                  radius: 28,
                  onTap: () => _goTo(const ProfileScreen()),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _isLoadingRole
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _fullName != null ? 'Hoşgeldin, $_fullName' : 'Hoşgeldin',
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(roleIcon(_role), size: 14, color: Theme.of(context).colorScheme.primary),
                                const SizedBox(width: 4),
                                Text(
                                  _departmentLabel != null ? '$roleLabel — $_departmentLabel' : roleLabel,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Talep ve Şikâyet Yönetim Sistemi',
              style: TextStyle(color: onSurface.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 24),
            const Text('Hızlı Eylemler', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _goTo(const RequestCreateScreen()),
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Talep Oluştur'),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
              ),
            ),
            const SizedBox(height: 28),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _buildSummaryCard(
                  title: 'Taleplerim',
                  counts: _myRequestCounts,
                  onTap: () => _goTo(const MyRequestsScreen()),
                ),
                if (!_isLoadingRole && _canViewIncoming)
                  _buildSummaryCard(
                    title: 'Gelen Talepler',
                    counts: _incomingRequestCounts,
                    onTap: () => _goTo(const RequestListScreen()),
                  ),
                _buildLatestRequestCard(),
              ],
            ),
            if (!_isLoadingRole && (_role == 'admin' || _role == 'mudur')) ...[
              const SizedBox(height: 16),
              _buildMiniStatsDashboard(),
            ],
          ],
        ),
      ),
    );
  }
}

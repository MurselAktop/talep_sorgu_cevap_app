import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';
import '../widgets/app_nav_route.dart';
import '../widgets/navigation_shell.dart';
import '../widgets/request_filters.dart';
import '../widgets/stats_dashboard_widgets.dart';
import '../widgets/status_badge.dart';

/// Admin'in tüm birimlerin talep istatistiklerini gerçek bir dashboard
/// olarak (KPI kartları, birim×durum çubuk grafiği, genel durum dağılımı
/// pasta grafiği, aylık çözüm süresi trendi) gördüğü ekran (Faz 5 →
/// dashboard genişlemesi, 2026-07-22). `get_admin_stats()` birim+durum
/// bazında gruplanmış sayıları, `get_admin_resolution_trend()` aylık
/// ortalama çözüm süresini döndürüyor — ikisi paralel (`Future.wait`) çekilir.
class AdminStatsScreen extends StatefulWidget {
  const AdminStatsScreen({super.key});

  @override
  State<AdminStatsScreen> createState() => _AdminStatsScreenState();
}

class _AdminStatsScreenState extends State<AdminStatsScreen> {
  static SupabaseClient get _client => SupabaseService.client;

  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _trendRows = [];
  List<Map<String, dynamic>> _personnelRatings = [];
  bool _isLoading = true;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      _isLoading = true;
      _errorText = null;
    });
    try {
      final results = await Future.wait([
        _client.rpc('get_admin_stats'),
        _client.rpc('get_admin_resolution_trend'),
        _client.rpc('get_personnel_ratings'),
      ]);
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(results[0] as List);
        _trendRows = List<Map<String, dynamic>>.from(results[1] as List);
        _personnelRatings = List<Map<String, dynamic>>.from(results[2] as List);
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _errorText = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorText = 'İstatistikler yüklenemedi. Lütfen tekrar deneyin.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final byDepartment = <String, List<Map<String, dynamic>>>{};
    for (final row in _rows) {
      final departmentName = row['department_name'] as String;
      byDepartment.putIfAbsent(departmentName, () => []).add(row);
    }

    // Durum bazlı toplamlar (tüm birimler birleştirilmiş) — KPI kartları ve
    // pasta grafiği bunu kullanıyor; birim×durum kırılımı zaten çubuk
    // grafikte ayrıca gösteriliyor.
    final statusTotals = <String, int>{};
    for (final row in _rows) {
      final status = row['status'] as String;
      statusTotals[status] = (statusTotals[status] ?? 0) + (row['request_count'] as int);
    }
    final totalCount = statusTotals.values.fold<int>(0, (sum, count) => sum + count);

    // Faz 6 (2026-07-23) — birim bazlı ortalama puan: her personelin
    // ortalamasını kendi biriminin toplamına puan-sayısı ağırlıklı olarak
    // katıyoruz (bir personelin tek puanı, 10 puanı olan başka bir personelle
    // aynı ağırlıkta sayılmasın diye).
    final departmentRatingWeightedSum = <String, double>{};
    final departmentRatingCount = <String, int>{};
    for (final row in _personnelRatings) {
      final departmentName = row['department_name'] as String?;
      final avgRating = (row['avg_rating'] as num?)?.toDouble();
      final ratingCount = row['rating_count'] as int? ?? 0;
      if (departmentName == null || avgRating == null || ratingCount == 0) continue;
      departmentRatingWeightedSum[departmentName] =
          (departmentRatingWeightedSum[departmentName] ?? 0) + (avgRating * ratingCount);
      departmentRatingCount[departmentName] = (departmentRatingCount[departmentName] ?? 0) + ratingCount;
    }
    final departmentRatings = <String, double>{
      for (final entry in departmentRatingCount.entries)
        entry.key: departmentRatingWeightedSum[entry.key]! / entry.value,
    };

    return NavigationShell(
      currentRoute: AppNavRoute.stats,
      title: 'İstatistikler (Tüm Birimler)',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Yenile',
          onPressed: _isLoading ? null : _loadStats,
        ),
      ],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorText != null
          ? Center(child: Text(_errorText!))
          : _rows.isEmpty
          ? const Center(child: Text('Henüz talep bulunmuyor.'))
          : RefreshIndicator(
              onRefresh: _loadStats,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      KpiCard(label: 'Toplam Talep', value: totalCount, color: Colors.indigo),
                      for (final status in const [
                        'acik',
                        'cozuldu',
                        'onaylandi',
                        'reddedildi',
                      ])
                        KpiCard(
                          label: statusLabels[status] ?? status,
                          value: statusTotals[status] ?? 0,
                          color: statusColors[status] ?? Colors.grey,
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: PagedDepartmentStatusChart(byDepartment: byDepartment),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Genel Durum Dağılımı',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 8),
                          StatusPieChart(statusCounts: statusTotals),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Aylık Ortalama Çözüm Süresi (saat)',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 16),
                          ResolutionTrendChart(trendRows: _trendRows),
                        ],
                      ),
                    ),
                  ),
                  if (departmentRatings.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: PagedDepartmentRatingChart(departmentRatings: departmentRatings),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

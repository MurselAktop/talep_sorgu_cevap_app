import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';
import '../widgets/app_nav_route.dart';
import '../widgets/navigation_shell.dart';
import '../widgets/request_filters.dart';
import '../widgets/star_rating.dart';
import '../widgets/stats_dashboard_widgets.dart';
import '../widgets/status_badge.dart';

/// Müdürün kendi biriminin talep istatistiklerini gerçek bir dashboard
/// olarak (KPI kartları, durum dağılımı pasta grafiği, aylık çözüm süresi
/// trendi) gördüğü ekran (Faz 5 → dashboard genişlemesi, 2026-07-22).
/// `get_manager_stats()`/`get_manager_resolution_trend()` zaten çağıranın
/// kendi birimine göre filtreleyip döndürüyor (`current_user_department()`)
/// — admin_stats_screen.dart'ın aksine BİRİM×DURUM çubuk grafiği YOK: tek
/// birim olduğu için bir birim ekseni anlamsız olurdu (kullanıcı kararı),
/// zaten durum dağılımı pasta grafiğinde ayrıca gösteriliyor.
class ManagerStatsScreen extends StatefulWidget {
  const ManagerStatsScreen({super.key});

  @override
  State<ManagerStatsScreen> createState() => _ManagerStatsScreenState();
}

class _ManagerStatsScreenState extends State<ManagerStatsScreen> {
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
        _client.rpc('get_manager_stats'),
        _client.rpc('get_manager_resolution_trend'),
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
    final statusTotals = <String, int>{};
    for (final row in _rows) {
      final status = row['status'] as String;
      statusTotals[status] = (statusTotals[status] ?? 0) + (row['request_count'] as int);
    }
    final totalCount = statusTotals.values.fold<int>(0, (sum, count) => sum + count);

    // Faz 6 (2026-07-23) — birimin genel ortalama puanı: personel bazlı
    // ortalamaların puan-sayısı ağırlıklı toplamı (bkz. admin_stats_screen.dart
    // içindeki aynı hesaplamanın gerekçesi).
    var weightedSum = 0.0;
    var weightedCount = 0;
    for (final row in _personnelRatings) {
      final avgRating = (row['avg_rating'] as num?)?.toDouble();
      final ratingCount = row['rating_count'] as int? ?? 0;
      if (avgRating == null || ratingCount == 0) continue;
      weightedSum += avgRating * ratingCount;
      weightedCount += ratingCount;
    }
    final departmentAvgRating = weightedCount == 0 ? null : weightedSum / weightedCount;

    return NavigationShell(
      currentRoute: AppNavRoute.stats,
      title: 'İstatistikler (Birimim)',
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
                  if (departmentAvgRating != null) ...[
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        // Uzun etiket + StarRatingDisplay yan yana dar ekranda
                        // taştığı için (sarı-siyah OVERFLOW şeridi) puanı
                        // etiketin altına alıyoruz.
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.star, color: Colors.amber),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Birimin Ortalama Değerlendirme Puanı',
                                    style: TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 4),
                                  StarRatingDisplay(
                                    rating: departmentAvgRating,
                                    ratingCount: weightedCount,
                                    size: 18,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Durum Dağılımı',
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
                ],
              ),
            ),
    );
  }
}

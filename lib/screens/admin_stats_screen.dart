import 'package:fl_chart/fl_chart.dart';
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Birim × Durum Dağılımı',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 16),
                          _DepartmentStatusBarChart(byDepartment: byDepartment),
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Birim Bazlı Ortalama Değerlendirme Puanı',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 16),
                            _DepartmentRatingBarChart(departmentRatings: departmentRatings),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

/// Birim bazlı ortalama puan çubuk grafiği (Faz 6, 2026-07-23) — y ekseni
/// sabit 0-5 (yıldız skalası), her çubuğun üstünde `StarRatingDisplay` ile
/// aynı sayısal biçim ("4.5") gösterilir.
class _DepartmentRatingBarChart extends StatelessWidget {
  const _DepartmentRatingBarChart({required this.departmentRatings});

  final Map<String, double> departmentRatings;

  @override
  Widget build(BuildContext context) {
    final departments = departmentRatings.keys.toList();

    return SizedBox(
      height: 240,
      child: BarChart(
        BarChartData(
          maxY: 5,
          barGroups: [
            for (var i = 0; i < departments.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: departmentRatings[departments[i]]!,
                    color: Colors.amber,
                    width: 22,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ),
          ],
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  final i = value.round();
                  if (i < 0 || i >= departments.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      departments[i],
                      style: const TextStyle(fontSize: 10),
                      textAlign: TextAlign.center,
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: const FlGridData(show: true),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                  BarTooltipItem(rod.toY.toStringAsFixed(1), const TextStyle(color: Colors.white)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Sadece bu ekranda kullanılan birim×durum gruplu çubuk grafiği — müdür
/// ekranında tek birim olduğu için birim ekseni gereksiz (bkz.
/// manager_stats_screen.dart), bu yüzden stats_dashboard_widgets.dart'a
/// (paylaşılan dosyaya) taşınmadı.
class _DepartmentStatusBarChart extends StatelessWidget {
  const _DepartmentStatusBarChart({required this.byDepartment});

  final Map<String, List<Map<String, dynamic>>> byDepartment;

  static const _statuses = ['acik', 'cozuldu', 'onaylandi', 'reddedildi', 'iptal'];

  int _countFor(List<Map<String, dynamic>> rows, String status) {
    for (final row in rows) {
      if (row['status'] == status) return row['request_count'] as int;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final departments = byDepartment.keys.toList();
    var maxCount = 0;
    for (final rows in byDepartment.values) {
      for (final row in rows) {
        final count = row['request_count'] as int;
        if (count > maxCount) maxCount = count;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 260,
          child: BarChart(
            BarChartData(
              maxY: (maxCount + 1).toDouble(),
              barGroups: [
                for (var i = 0; i < departments.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      for (final status in _statuses)
                        BarChartRodData(
                          toY: _countFor(byDepartment[departments[i]]!, status).toDouble(),
                          color: statusColors[status],
                          width: 6,
                        ),
                    ],
                  ),
              ],
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (value, meta) {
                      final i = value.round();
                      if (i < 0 || i >= departments.length) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          departments[i],
                          style: const TextStyle(fontSize: 10),
                          textAlign: TextAlign.center,
                        ),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: true, reservedSize: 32),
                ),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: const FlGridData(show: true),
              borderData: FlBorderData(show: false),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          alignment: WrapAlignment.center,
          children: [
            for (final status in _statuses)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 10, height: 10, color: statusColors[status]),
                  const SizedBox(width: 4),
                  Text(statusLabels[status] ?? status, style: const TextStyle(fontSize: 12)),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

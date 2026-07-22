import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';
import '../widgets/request_filters.dart';
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
      ]);
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(results[0] as List);
        _trendRows = List<Map<String, dynamic>>.from(results[1] as List);
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('İstatistikler (Birimim)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Yenile',
            onPressed: _isLoading ? null : _loadStats,
          ),
        ],
      ),
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

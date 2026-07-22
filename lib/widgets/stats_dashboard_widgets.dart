import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'request_filters.dart' show statusLabels;
import 'status_badge.dart' show statusColors;

/// admin_stats_screen.dart ve manager_stats_screen.dart arasında paylaşılan
/// dashboard parçaları (KPI kartı, durum dağılımı pasta grafiği, çözüm süresi
/// trendi çizgi grafiği). Birim×durum çubuk grafiği burada YOK — sadece
/// admin_stats_screen.dart'ta kullanılıyor (müdürde tek birim olduğu için
/// birim ekseni gereksiz, bkz. o dosyadaki gerekçe), tek kullanım yeri olan
/// bir şeyi burada paylaşıma açmak gereksiz soyutlama olurdu.

/// Tek bir KPI sayısı (ör. "Açık: 12") kartı.
class KpiCard extends StatelessWidget {
  const KpiCard({super.key, required this.label, required this.value, required this.color});

  final String label;
  final int value;
  final MaterialColor color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 128),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$value',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color.shade900),
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 12, color: color.shade700)),
        ],
      ),
    );
  }
}

/// `requests.status` → sayı toplamlarından (ör. `{'acik': 5, 'onaylandi': 3}`)
/// donut bir pasta grafik + altında renk lejantı çizer. `statusCounts`
/// tamamen boşsa (toplam 0) hiçbir şey çizmez — çağıran taraf zaten genel
/// "henüz veri yok" durumunu ayrıca ele alıyor, burada sessizce boş kalması
/// yeterli.
class StatusPieChart extends StatelessWidget {
  const StatusPieChart({super.key, required this.statusCounts});

  final Map<String, int> statusCounts;

  @override
  Widget build(BuildContext context) {
    final entries = statusCounts.entries.where((e) => e.value > 0).toList();
    final total = entries.fold<int>(0, (sum, e) => sum + e.value);
    if (total == 0) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text('Henüz veri yok.')),
      );
    }

    return Column(
      children: [
        SizedBox(
          height: 200,
          child: PieChart(
            PieChartData(
              sections: [
                for (final entry in entries)
                  PieChartSectionData(
                    value: entry.value.toDouble(),
                    color: statusColors[entry.key] ?? Colors.grey,
                    title: '${(entry.value / total * 100).round()}%',
                    radius: 70,
                    titleStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
              ],
              sectionsSpace: 2,
              centerSpaceRadius: 40,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          alignment: WrapAlignment.center,
          children: [
            for (final entry in entries)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    color: statusColors[entry.key] ?? Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${statusLabels[entry.key] ?? entry.key} (${entry.value})',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

double? _asDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

const List<String> _monthAbbreviations = [
  'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara',
];

String _formatPeriod(String isoDate) {
  final date = DateTime.parse(isoDate);
  return '${_monthAbbreviations[date.month - 1]} ${date.year}';
}

/// `get_admin_resolution_trend()`/`get_manager_resolution_trend()`
/// RPC'lerinin döndürdüğü (`period_start`, `avg_resolution_hours`,
/// `request_count`) satırlarını aylık ortalama çözüm süresi çizgi grafiği
/// olarak çizer. `resolved_at`'ı NULL olan kayıtlar RPC tarafında zaten
/// hariç tutuluyor (bkz. migration'daki gerekçe) — burada sadece dönen ilk
/// (en eski) dönemi "X tarihinden itibaren veri mevcuttur" notunda kullanıyoruz.
class ResolutionTrendChart extends StatelessWidget {
  const ResolutionTrendChart({super.key, required this.trendRows});

  final List<Map<String, dynamic>> trendRows;

  @override
  Widget build(BuildContext context) {
    if (trendRows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text('Henüz çözüm süresi verisi yok.')),
      );
    }

    final spots = <FlSpot>[
      for (var i = 0; i < trendRows.length; i++)
        FlSpot(i.toDouble(), _asDouble(trendRows[i]['avg_resolution_hours']) ?? 0),
    ];
    final firstPeriodLabel = _formatPeriod(trendRows.first['period_start'] as String);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 220,
          child: LineChart(
            LineChartData(
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  color: Colors.deepPurple,
                  barWidth: 3,
                  dotData: const FlDotData(show: true),
                  belowBarData: BarAreaData(
                    show: true,
                    color: Colors.deepPurple.withValues(alpha: 0.1),
                  ),
                ),
              ],
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (value, meta) {
                      final i = value.round();
                      if (i < 0 || i >= trendRows.length) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _formatPeriod(trendRows[i]['period_start'] as String),
                          style: const TextStyle(fontSize: 10),
                        ),
                      );
                    },
                  ),
                ),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: const FlGridData(show: true),
              borderData: FlBorderData(show: false),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '$firstPeriodLabel tarihinden itibaren veri mevcuttur (yalnızca onaylanmış talepler dahil edilir).',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
        ),
      ],
    );
  }
}

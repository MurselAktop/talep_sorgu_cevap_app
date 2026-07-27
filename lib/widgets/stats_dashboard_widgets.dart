import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'request_filters.dart' show statusLabels;
import 'status_badge.dart' show statusColors;

/// Tek bir KPI sayısı — değer 0'dan hedefe animasyonla artar (2026-07-27).
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
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value.toDouble()),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, animated, _) => Text(
              '${animated.round()}',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color.shade900),
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 12, color: color.shade700)),
        ],
      ),
    );
  }
}

/// Sayfa noktaları (grafik altı sekme geçişi) — en fazla 3 birim/sayfa.
class ChartPageDots extends StatelessWidget {
  const ChartPageDots({
    super.key,
    required this.pageCount,
    required this.currentPage,
    required this.onPageSelected,
  });

  final int pageCount;
  final int currentPage;
  final ValueChanged<int> onPageSelected;

  @override
  Widget build(BuildContext context) {
    if (pageCount <= 1) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < pageCount; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => onPageSelected(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: i == currentPage ? 12 : 10,
                  height: i == currentPage ? 12 : 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == currentPage
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey.shade400,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Grafik kartı başlığı + büyütme butonu.
class ChartCardHeader extends StatelessWidget {
  const ChartCardHeader({super.key, required this.title, this.onExpand});

  final String title;
  final VoidCallback? onExpand;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
        if (onExpand != null)
          IconButton(
            tooltip: 'Büyüt',
            icon: const Icon(Icons.open_in_full, size: 20),
            onPressed: onExpand,
          ),
      ],
    );
  }
}

/// Büyütülmüş grafik diyaloğu — solda grafik, sağda (veya altta) detay listesi.
Future<void> showExpandedChartDialog({
  required BuildContext context,
  required String title,
  required Widget chart,
  required Widget details,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final size = MediaQuery.sizeOf(dialogContext);
      final wide = size.width >= 700;
      return Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: size.width * 0.95,
          height: size.height * 0.85,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(dialogContext).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: wide
                    ? Row(
                        children: [
                          Expanded(flex: 3, child: Padding(padding: const EdgeInsets.all(16), child: chart)),
                          const VerticalDivider(width: 1),
                          Expanded(flex: 2, child: details),
                        ],
                      )
                    : Column(
                        children: [
                          Expanded(flex: 3, child: Padding(padding: const EdgeInsets.all(12), child: chart)),
                          const Divider(height: 1),
                          Expanded(flex: 2, child: details),
                        ],
                      ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

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
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, t, _) => PieChart(
              PieChartData(
                sections: [
                  for (final entry in entries)
                    PieChartSectionData(
                      value: entry.value.toDouble() * t,
                      color: statusColors[entry.key] ?? Colors.grey,
                      title: t > 0.7 ? '${(entry.value / total * 100).round()}%' : '',
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
                  Container(width: 10, height: 10, color: statusColors[entry.key] ?? Colors.grey),
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
    final lineColor = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 220,
          child: LineChart(
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            LineChartData(
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  color: lineColor,
                  barWidth: 3,
                  dotData: const FlDotData(show: true),
                  belowBarData: BarAreaData(show: true, color: lineColor.withValues(alpha: 0.1)),
                ),
              ],
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
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

String _shortDeptLabel(String name) {
  if (name.length <= 12) return name;
  return '${name.substring(0, 11)}…';
}

/// Birim bazlı ortalama puan — sayfa başına 3 birim + nokta geçişi + büyütme.
class PagedDepartmentRatingChart extends StatefulWidget {
  const PagedDepartmentRatingChart({super.key, required this.departmentRatings});

  final Map<String, double> departmentRatings;

  @override
  State<PagedDepartmentRatingChart> createState() => _PagedDepartmentRatingChartState();
}

class _PagedDepartmentRatingChartState extends State<PagedDepartmentRatingChart> {
  static const _pageSize = 3;
  int _page = 0;

  List<String> get _all => widget.departmentRatings.keys.toList()..sort();
  int get _pageCount => (_all.length / _pageSize).ceil().clamp(1, 999);
  List<String> get _pageItems {
    final start = _page * _pageSize;
    return _all.sublist(start, (start + _pageSize).clamp(0, _all.length));
  }

  Widget _buildChart(List<String> departments, {required bool expanded}) {
    return TweenAnimationBuilder<double>(
      key: ValueKey('rating-$_page-$expanded'),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => BarChart(
        duration: Duration.zero,
        BarChartData(
          maxY: 5,
          barGroups: [
            for (var i = 0; i < departments.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: (widget.departmentRatings[departments[i]] ?? 0) * t,
                    color: Colors.amber,
                    width: expanded ? 28 : 22,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
                showingTooltipIndicators: const [0],
              ),
          ],
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: expanded ? 48 : 40,
                getTitlesWidget: (value, meta) {
                  final i = value.round();
                  if (i < 0 || i >= departments.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      expanded ? departments[i] : _shortDeptLabel(departments[i]),
                      style: TextStyle(fontSize: expanded ? 11 : 10),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                },
              ),
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: const FlGridData(show: true),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                rod.toY.toStringAsFixed(1),
                const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetails(List<String> departments) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Detaylı Puanlar', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        for (final name in departments)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(name),
            trailing: Text(
              (widget.departmentRatings[name] ?? 0).toStringAsFixed(1),
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.amber),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _pageItems;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChartCardHeader(
          title: 'Birim Bazlı Ortalama Değerlendirme Puanı',
          onExpand: () => showExpandedChartDialog(
            context: context,
            title: 'Birim Bazlı Ortalama Değerlendirme Puanı',
            chart: _buildChart(items, expanded: true),
            details: _buildDetails(items),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(height: 240, child: _buildChart(items, expanded: false)),
        ChartPageDots(
          pageCount: _pageCount,
          currentPage: _page.clamp(0, _pageCount - 1),
          onPageSelected: (p) => setState(() => _page = p),
        ),
      ],
    );
  }
}

/// Birim × durum dağılımı — sayfa başına 3 birim + nokta geçişi + büyütme.
class PagedDepartmentStatusChart extends StatefulWidget {
  const PagedDepartmentStatusChart({super.key, required this.byDepartment});

  final Map<String, List<Map<String, dynamic>>> byDepartment;

  @override
  State<PagedDepartmentStatusChart> createState() => _PagedDepartmentStatusChartState();
}

class _PagedDepartmentStatusChartState extends State<PagedDepartmentStatusChart> {
  static const _pageSize = 3;
  static const _statuses = ['acik', 'cozuldu', 'onaylandi', 'reddedildi', 'iptal'];
  int _page = 0;

  List<String> get _all => widget.byDepartment.keys.toList()..sort();
  int get _pageCount => (_all.length / _pageSize).ceil().clamp(1, 999);
  List<String> get _pageItems {
    final start = _page * _pageSize;
    return _all.sublist(start, (start + _pageSize).clamp(0, _all.length));
  }

  int _countFor(List<Map<String, dynamic>> rows, String status) {
    for (final row in rows) {
      if (row['status'] == status) return row['request_count'] as int;
    }
    return 0;
  }

  Widget _buildChart(List<String> departments, {required bool expanded}) {
    var maxCount = 0;
    for (final name in departments) {
      for (final row in widget.byDepartment[name] ?? const []) {
        final count = row['request_count'] as int;
        if (count > maxCount) maxCount = count;
      }
    }

    return TweenAnimationBuilder<double>(
      key: ValueKey('status-$_page-$expanded'),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => BarChart(
        duration: Duration.zero,
        BarChartData(
          maxY: (maxCount + 1).toDouble(),
          barGroups: [
            for (var i = 0; i < departments.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  for (final status in _statuses)
                    BarChartRodData(
                      toY: _countFor(widget.byDepartment[departments[i]]!, status).toDouble() * t,
                      color: statusColors[status],
                      width: expanded ? 8 : 6,
                    ),
                ],
              ),
          ],
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: expanded ? 48 : 40,
                getTitlesWidget: (value, meta) {
                  final i = value.round();
                  if (i < 0 || i >= departments.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      expanded ? departments[i] : _shortDeptLabel(departments[i]),
                      style: TextStyle(fontSize: expanded ? 11 : 10),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                },
              ),
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: const FlGridData(show: true),
          borderData: FlBorderData(show: false),
        ),
      ),
    );
  }

  Widget _buildDetails(List<String> departments) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Detaylı Dağılım', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        for (final name in departments) ...[
          Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          for (final status in _statuses)
            if (_countFor(widget.byDepartment[name]!, status) > 0)
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 2),
                child: Row(
                  children: [
                    Container(width: 10, height: 10, color: statusColors[status]),
                    const SizedBox(width: 6),
                    Expanded(child: Text(statusLabels[status] ?? status)),
                    Text('${_countFor(widget.byDepartment[name]!, status)}'),
                  ],
                ),
              ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _legend() {
    return Wrap(
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _pageItems;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChartCardHeader(
          title: 'Birim × Durum Dağılımı',
          onExpand: () => showExpandedChartDialog(
            context: context,
            title: 'Birim × Durum Dağılımı',
            chart: Column(
              children: [
                Expanded(child: _buildChart(items, expanded: true)),
                const SizedBox(height: 8),
                _legend(),
              ],
            ),
            details: _buildDetails(items),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(height: 260, child: _buildChart(items, expanded: false)),
        const SizedBox(height: 12),
        _legend(),
        ChartPageDots(
          pageCount: _pageCount,
          currentPage: _page.clamp(0, _pageCount - 1),
          onPageSelected: (p) => setState(() => _page = p),
        ),
      ],
    );
  }
}

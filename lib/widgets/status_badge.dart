import 'package:flutter/material.dart';

import 'request_filters.dart' show statusLabels;

/// `requests.status` → renk eşlemesi. Tek kaynak — hem `StatusBadge` hem
/// istatistik dashboard'larındaki (admin_stats_screen.dart,
/// manager_stats_screen.dart) KPI kartları/grafikler aynı paleti kullanır,
/// böylece rozetle grafik renkleri arasında tutarsızlık olmaz.
const Map<String, MaterialColor> statusColors = {
  'acik': Colors.orange,
  'cozuldu': Colors.blue,
  'onaylandi': Colors.green,
  'reddedildi': Colors.red,
  'iptal': Colors.grey,
};

/// Talep durumunu (`requests.status`) renkli bir rozet olarak gösterir.
/// Etiket metni, tek kaynaktan yönetilmesi için request_filters.dart'taki
/// paylaşılan `statusLabels` map'inden geliyor; renk şeması bu ekranın
/// (request_list_screen.dart) zaten kullandığı "Atanmadı/Atanmış" Chip'iyle
/// aynı görsel dili (shade900 metin, shade100 arka plan) izliyor.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = statusColors[status] ?? Colors.grey;
    return Chip(
      label: Text(statusLabels[status] ?? status),
      labelStyle: TextStyle(fontSize: 12, color: color.shade900),
      backgroundColor: color.shade100,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: EdgeInsets.zero,
    );
  }
}

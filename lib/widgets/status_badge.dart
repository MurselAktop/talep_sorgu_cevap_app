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

/// Bir `MaterialColor`'ı (ör. `statusColors`'tan) hem açık hem koyu temada
/// okunaklı bir (arkaplan, yazı) çiftine çevirir — açık temada soluk/pastel
/// arka plan + koyu yazı (`shade100`/`shade900`, `request_list_screen.dart`'ın
/// zaten kullandığı "Atanmadı/Atanmış" chip'iyle aynı görsel dil), koyu
/// temada ise (`app_theme.dart`) doygun/orta ton arka plan + beyaz yazı —
/// aksi halde açık temaya göre seçilmiş soluk bir chip, koyu (#121212)
/// arka planda okunaksız bir "beyaz leke" gibi görünürdü. `StatusBadge`,
/// `KpiCard` (stats_dashboard_widgets.dart) ve talep detayındaki "daha önce
/// reddedilmiş"/"Atanmadı-Atanmış" chip'leri hep bunu kullanır — tek kaynak.
({Color background, Color foreground}) tonalColors(BuildContext context, MaterialColor color) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark
      ? (background: color.shade700, foreground: Colors.white)
      : (background: color.shade100, foreground: color.shade900);
}

/// Talep durumunu (`requests.status`) renkli bir rozet olarak gösterir.
/// Etiket metni, tek kaynaktan yönetilmesi için request_filters.dart'taki
/// paylaşılan `statusLabels` map'inden geliyor; renk şeması [tonalColors]
/// ile açık/koyu temaya göre uyarlanıyor.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = statusColors[status] ?? Colors.grey;
    final tones = tonalColors(context, color);
    return Chip(
      label: Text(statusLabels[status] ?? status),
      labelStyle: TextStyle(fontSize: 12, color: tones.foreground),
      backgroundColor: tones.background,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: EdgeInsets.zero,
    );
  }
}

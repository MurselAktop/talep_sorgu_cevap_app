const List<String> _turkishMonths = [
  'Ocak',
  'Şubat',
  'Mart',
  'Nisan',
  'Mayıs',
  'Haziran',
  'Temmuz',
  'Ağustos',
  'Eylül',
  'Ekim',
  'Kasım',
  'Aralık',
];

/// `notifications_screen.dart`'taki `_formatDateTime` ile AYNI biçim
/// ("gün Ay yıl saat:dakika", Türkçe ay adlarıyla, intl paketine ihtiyaç
/// duymadan) — DM ekranlarında (Faz 7, 2026-07-23) tekrar kod yazılmaması
/// için paylaşılan bir yardımcıya çıkarıldı.
String formatTurkishDateTime(String? isoString) {
  if (isoString == null) return '';
  final date = DateTime.tryParse(isoString);
  if (date == null) return isoString;

  final local = date.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = _turkishMonths[local.month - 1];
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day $month ${local.year} $hour:$minute';
}

/// Konuşma listesinde son mesaj zamanı için daha kısa, "bugün/dün/tarih"
/// tarzı bir gösterim — sohbet uygulamalarındaki alışılmış desen.
String formatTurkishRelativeDateTime(String? isoString) {
  if (isoString == null) return '';
  final date = DateTime.tryParse(isoString);
  if (date == null) return isoString;

  final local = date.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final messageDay = DateTime(local.year, local.month, local.day);
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');

  if (messageDay == today) return '$hour:$minute';
  if (messageDay == today.subtract(const Duration(days: 1))) return 'Dün $hour:$minute';
  return '${local.day.toString().padLeft(2, '0')} ${_turkishMonths[local.month - 1]}';
}

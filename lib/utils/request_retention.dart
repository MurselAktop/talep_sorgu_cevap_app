/// Onaylanmış taleplerin 3 ay sonra otomatik silinmesi (2026-07-27).
///
/// `resolved_at` + 3 ay = silinme tarihi. UI'da kalan süre hafif gri yazıyla
/// gösterilir; asıl silme `purge_expired_requests()` RPC'siyle yapılır.
class RequestRetention {
  static const retentionDays = 90; // ~3 ay

  static DateTime? deletionDeadline(String? resolvedAtIso) {
    final resolved = resolvedAtIso == null ? null : DateTime.tryParse(resolvedAtIso);
    if (resolved == null) return null;
    return resolved.toLocal().add(const Duration(days: retentionDays));
  }

  /// `onaylandi` talepler için "Silinmesine X gün kaldı" metni; diğer durumda null.
  static String? remainingLabel({
    required String? status,
    required String? resolvedAtIso,
  }) {
    if (status != 'onaylandi') return null;
    final deadline = deletionDeadline(resolvedAtIso);
    if (deadline == null) return null;

    final now = DateTime.now();
    final remaining = deadline.difference(now);
    if (remaining.isNegative) {
      return 'Bu talep yakında otomatik silinecek';
    }
    final days = remaining.inDays;
    if (days <= 0) {
      return 'Bu talep bugün otomatik silinebilir';
    }
    if (days == 1) {
      return 'Silinmesine 1 gün kaldı';
    }
    return 'Silinmesine $days gün kaldı';
  }
}

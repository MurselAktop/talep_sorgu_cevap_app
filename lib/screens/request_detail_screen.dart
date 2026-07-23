import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';
import '../widgets/star_rating.dart';
import '../widgets/status_badge.dart';

/// `requests.requester_type` ham değerlerinin Türkçe karşılıkları.
const Map<String, String> _requesterTypeLabels = {
  'vatandas': 'Vatandaş',
  'anonim': 'Anonim',
  'personel': 'Personel',
};

/// `results.approval_status` ham değerlerinin Türkçe karşılıkları.
const Map<String, String> _approvalStatusLabels = {
  'beklemede': 'Onay Bekliyor',
  'onaylandi': 'Onaylandı',
  'reddedildi': 'Reddedildi',
};

/// Faz 6 (2026-07-23) — `request_history.event_type` ham değerlerinin Türkçe
/// etiketi/ikonu/rengi. `actor_label` zaten yazma anında (trigger/RPC içinde,
/// gizlilik kuralına uygun şekilde) hazırlandığı için burada sadece olay
/// TÜRÜNÜ göstermek yeterli — bkz. migration'daki mimari not.
const Map<String, String> _historyEventLabels = {
  'created': 'Talep oluşturuldu',
  'assigned': 'Personele atandı',
  'department_changed': 'Birim değiştirildi',
  'resolved': 'Çözüm raporu gönderildi',
  'report_resubmitted': 'Rapor yeniden gönderildi',
  'approved': 'Onaylandı',
  'rejected': 'Reddedildi',
  'reopened': 'Yeniden açıldı',
  'rated': 'Değerlendirildi',
};

const Map<String, IconData> _historyEventIcons = {
  'created': Icons.add_circle_outline,
  'assigned': Icons.person_add_alt,
  'department_changed': Icons.swap_horiz,
  'resolved': Icons.description_outlined,
  'report_resubmitted': Icons.edit_note,
  'approved': Icons.check_circle_outline,
  'rejected': Icons.cancel_outlined,
  'reopened': Icons.replay_circle_filled_outlined,
  'rated': Icons.star_outline,
};

const Map<String, Color> _historyEventColors = {
  'created': Colors.blue,
  'assigned': Colors.indigo,
  'department_changed': Colors.teal,
  'resolved': Colors.orange,
  'report_resubmitted': Colors.deepOrange,
  'approved': Colors.green,
  'rejected': Colors.red,
  'reopened': Colors.purple,
  'rated': Colors.amber,
};

/// Her olay tipi için `detail` jsonb içinden gösterilecek ek açıklama metni.
String? _historyDetailText(String eventType, Map<String, dynamic>? detail) {
  if (detail == null) return null;
  switch (eventType) {
    case 'assigned':
      return detail['personnel_name'] as String?;
    case 'department_changed':
      return '${detail['old_department_name']} → ${detail['new_department_name']}';
    case 'resolved':
    case 'report_resubmitted':
      return detail['report_text'] as String?;
    case 'reopened':
      final previousPersonnel = detail['previous_personnel_name'] as String?;
      return previousPersonnel == null ? null : 'Önceki personel: $previousPersonnel';
    case 'rated':
      final rating = detail['rating'];
      final comment = detail['comment'] as String?;
      final hasComment = comment != null && comment.isNotEmpty;
      return '$rating ★${hasComment ? ' — $comment' : ''}';
    default:
      return null;
  }
}

String _formatHistoryDate(String? isoDate) {
  final date = isoDate == null ? null : DateTime.tryParse(isoDate);
  if (date == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(date.day)}.${two(date.month)}.${date.year} ${two(date.hour)}:${two(date.minute)}';
}

/// Bir talebin tüm alanlarını gösteren detay ekranı. Liste ekranlarından
/// (request_list_screen.dart, my_requests_screen.dart) gelinir; listedeki
/// veriyi tekrar kullanmak yerine bilinçli olarak taze bir sorgu atılır
/// (talep, listeleme ile detay açılması arasında güncellenmiş olabilir).
/// Müdür, henüz kimseye atanmamış bir talebi burada birimindeki bir personele
/// atayabilir ve atanan personelin yazdığı raporu onaylayıp/reddedebilir;
/// atanan personel talebi çözüp rapor yazabilir, onay bekleyen veya
/// reddedilen kendi raporunu düzenleyebilir (bkz. CLAUDE.md — Talebi kim
/// açar, kim çözer / Talep durum akışı).
class RequestDetailScreen extends StatefulWidget {
  final String requestId;

  const RequestDetailScreen({super.key, required this.requestId});

  @override
  State<RequestDetailScreen> createState() => _RequestDetailScreenState();
}

/// Storage'a yüklenirken dosya adının önüne eklenen benzersizlik damgasını
/// (bkz. request_create_screen.dart — `{timestamp}_{dosyaAdı}`) kullanıcıya
/// göstermeden önce ayıklar.
String _originalFileName(String storagePath) {
  final fileName = storagePath.split('/').last;
  final match = RegExp(r'^\d+_(.+)$').firstMatch(fileName);
  return match?.group(1) ?? fileName;
}

/// Faz 5: `requests.resolved_at` doluysa (rapor onaylandığında set edilir)
/// oluşturulma ile çözülme arasındaki süreyi Türkçe "X gün Y saat" biçiminde
/// gösterir (intl paketi kullanılmıyor — notifications_screen.dart'taki
/// hand-rolled tarih formatlama deseniyle tutarlı).
String? _formatResolutionDuration(String? createdAt, String? resolvedAt) {
  if (createdAt == null || resolvedAt == null) return null;
  final created = DateTime.tryParse(createdAt);
  final resolved = DateTime.tryParse(resolvedAt);
  if (created == null || resolved == null) return null;

  final duration = resolved.difference(created);
  final days = duration.inDays;
  final hours = duration.inHours.remainder(24);

  if (days > 0) {
    return hours > 0 ? '$days gün $hours saat' : '$days gün';
  }
  if (duration.inHours > 0) {
    return '${duration.inHours} saat';
  }
  return '${duration.inMinutes} dakika';
}

class _RequestDetailScreenState extends State<RequestDetailScreen> {
  static SupabaseClient get _client => SupabaseService.client;

  Map<String, dynamic>? _request;
  Map<String, dynamic>? _result;
  List<Map<String, dynamic>> _attachments = [];
  bool _isLoading = true;
  String? _role;
  bool _isLoadingPersonnel = false;
  bool _isLoadingDepartmentsForReassign = false;

  // Faz 6 (2026-07-23) — puanlama + talep geçmişi.
  Map<String, dynamic>? _myRating;
  List<Map<String, dynamic>> _history = [];
  bool _isLoadingHistory = false;
  bool _isReopening = false;

  @override
  void initState() {
    super.initState();
    _loadRequest();
    _loadCurrentUserRole();
  }

  Future<void> _loadRequest() async {
    try {
      final requestResponse = await _client
          .from('requests')
          .select('*, departments(name)')
          .eq('id', widget.requestId)
          .single();
      // Talebe ait bir rapor henüz girilmemişse maybeSingle() null döner.
      final resultResponse = await _client
          .from('results')
          .select()
          .eq('request_id', widget.requestId)
          .maybeSingle();

      setState(() {
        _request = Map<String, dynamic>.from(requestResponse);
        _result = resultResponse == null ? null : Map<String, dynamic>.from(resultResponse);
      });
      await _loadAttachments();
      _maybeLoadRoleDependentSections();
    } on PostgrestException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Talep yüklenemedi. Lütfen tekrar deneyin.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin.')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Eklerin listelenmesi, talebin geri kalanının görüntülenmesi için kritik
  /// olmadığından hata durumunda sessizce yutulur (yalnızca ek şeridi boş
  /// kalır) — `_loadCurrentUserRole`'daki gerekçeyle aynı.
  Future<void> _loadAttachments() async {
    try {
      final response = await _client
          .from('attachments')
          .select('id, file_url, media_type')
          .eq('request_id', widget.requestId)
          .order('created_at');
      final attachments = List<Map<String, dynamic>>.from(response);

      await Future.wait(
        attachments.map((attachment) async {
          try {
            attachment['signed_url'] = await _client.storage
                .from('request-attachments')
                .createSignedUrl(attachment['file_url'] as String, 3600);
          } catch (_) {
            // İmzalı URL alınamazsa o ek için sadece önizleme gösterilmez,
            // dosya adı/ikon yine de listede kalır.
          }
        }),
      );

      if (mounted) setState(() => _attachments = attachments);
    } catch (_) {
      // Yukarıdaki dokümantasyona bakın.
    }
  }

  void _showImagePreview(String signedUrl) {
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(child: Image.network(signedUrl)),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        ),
      ),
    );
  }

  /// Rol bilgisi yalnızca "Ata" butonunun görünürlüğünü belirlediği için,
  /// okunamazsa sessizce yutulur — buton gösterilmez, ekranın geri kalanı
  /// (talep bilgileri) etkilenmez.
  Future<void> _loadCurrentUserRole() async {
    try {
      final userId = _client.auth.currentUser!.id;
      final profile = await _client
          .from('users')
          .select('role')
          .eq('id', userId)
          .single();
      if (mounted) setState(() => _role = profile['role'] as String);
      _maybeLoadRoleDependentSections();
    } catch (_) {
      // Sessizce yutulur, yukarıdaki dokümantasyona bakın.
    }
  }

  /// `_loadRequest()` ve `_loadCurrentUserRole()` paralel çalıştığı için
  /// (initState'te ikisi de ayrı ayrı tetiklenir), puanlama/geçmiş
  /// bölümlerinin ikisine de ihtiyacı olan bilgiler (talep + rol) hangi sırayla
  /// gelirse gelsin yüklensin diye her iki metodun sonunda da çağrılan ortak
  /// bir kapı fonksiyonu.
  void _maybeLoadRoleDependentSections() {
    if (_request == null || _role == null) return;
    _loadMyRating();
    _loadHistory();
  }

  /// Sadece talebi açan kişi + talep onaylanmışken anlamlı olduğu için diğer
  /// durumlarda hiç sorgu atmadan çıkar. Puanlama ikincil bir bilgi olduğundan
  /// hata durumunda sessizce yutulur (`_loadCurrentUserRole`'daki gerekçeyle
  /// aynı).
  Future<void> _loadMyRating() async {
    final request = _request;
    if (request == null) return;
    final isCreator = request['created_by'] == _client.auth.currentUser?.id;
    if (!isCreator || request['status'] != 'onaylandi') return;

    try {
      final row = await _client
          .from('request_ratings')
          .select('rating, comment')
          .eq('request_id', widget.requestId)
          .maybeSingle();
      if (mounted) {
        setState(() => _myRating = row == null ? null : Map<String, dynamic>.from(row));
      }
    } catch (_) {
      // Sessizce yutulur, yukarıdaki dokümantasyona bakın.
    }
  }

  /// Talep geçmişi (zaman çizelgesi) sadece personel/müdür/admin ekranlarında
  /// gösterilir (kullanıcı isteği + RLS'in `gorebilen_calisanlar_gecmisi_gorebilir`
  /// politikasıyla tutarlı).
  Future<void> _loadHistory() async {
    final role = _role;
    if (role == null || !['personel', 'mudur', 'admin'].contains(role)) return;

    setState(() => _isLoadingHistory = true);
    try {
      final rows = await _client
          .from('request_history')
          .select()
          .eq('request_id', widget.requestId)
          .order('created_at');
      if (mounted) setState(() => _history = List<Map<String, dynamic>>.from(rows));
    } catch (_) {
      // Sessizce yutulur, yukarıdaki dokümantasyona bakın.
    } finally {
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  void _showRateDialog() {
    final myRating = _myRating;
    showDialog(
      context: context,
      builder: (dialogContext) => _RateRequestDialog(
        initialRating: myRating?['rating'] as int? ?? 0,
        initialComment: myRating?['comment'] as String?,
        onSubmit: _submitRating,
      ),
    );
  }

  Future<void> _submitRating(BuildContext dialogContext, int rating, String comment) async {
    try {
      await _client.rpc(
        'rate_request',
        params: {
          'p_request_id': widget.requestId,
          'p_rating': rating,
          'p_comment': comment.isEmpty ? null : comment,
        },
      );

      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Değerlendirmeniz için teşekkürler.')),
      );
      await _loadMyRating();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin.')),
      );
    }
  }

  void _showReopenConfirmDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Talebi Yeniden Aç'),
        content: const Text(
          'Bu talebi yeniden açmak istediğinize emin misiniz? Talep tekrar "açık" '
          'duruma dönecek, ataması sıfırlanacak ve müdür tarafından yeniden bir '
          'personele atanacaktır.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: _isReopening ? null : () => _reopenRequest(dialogContext),
            child: const Text('Evet, Yeniden Aç'),
          ),
        ],
      ),
    );
  }

  Future<void> _reopenRequest(BuildContext dialogContext) async {
    setState(() => _isReopening = true);
    try {
      await _client.rpc('reopen_request', params: {'p_request_id': widget.requestId});

      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Talep yeniden açıldı.')),
      );
      await _loadRequest();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin.')),
      );
    } finally {
      if (mounted) setState(() => _isReopening = false);
    }
  }

  Future<void> _onAssignPressed() async {
    final request = _request;
    if (request == null) return;

    setState(() => _isLoadingPersonnel = true);
    try {
      final response = await _client
          .from('users')
          .select('id, full_name')
          .eq('department_id', request['department_id'])
          .eq('role', 'personel');
      final personnel = List<Map<String, dynamic>>.from(response);

      // Puanlar ikincil bir bilgi (Ata dialogunda personel seçimine yardımcı
      // olsun diye eklendi) — yüklenemezse dialog yine de açılır, sadece
      // yıldızlar gösterilmez.
      Map<String, Map<String, dynamic>> ratingsByPersonnelId = {};
      try {
        final ratingRows = await _client.rpc('get_personnel_ratings') as List;
        ratingsByPersonnelId = {
          for (final row in ratingRows) row['personnel_id'] as String: Map<String, dynamic>.from(row),
        };
      } catch (_) {
        // Sessizce yutulur, yukarıda açıklandı.
      }

      if (!mounted) return;
      _showAssignDialog(personnel, ratingsByPersonnelId);
    } on PostgrestException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Personel listesi yüklenemedi. Lütfen tekrar deneyin.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin.')),
      );
    } finally {
      if (mounted) setState(() => _isLoadingPersonnel = false);
    }
  }

  void _showAssignDialog(
    List<Map<String, dynamic>> personnel,
    Map<String, Map<String, dynamic>> ratingsByPersonnelId,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Personele Ata'),
        content: SizedBox(
          width: double.maxFinite,
          child: personnel.isEmpty
              ? const Text('Bu birimde henüz personel yok.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: personnel.length,
                  itemBuilder: (context, index) {
                    final person = personnel[index];
                    final ratingInfo = ratingsByPersonnelId[person['id']];
                    final avgRating = ratingInfo?['avg_rating'] as num?;
                    final ratingCount = ratingInfo?['rating_count'] as int?;
                    return ListTile(
                      title: Text(person['full_name'] as String? ?? ''),
                      subtitle: StarRatingDisplay(
                        rating: avgRating?.toDouble(),
                        ratingCount: ratingCount,
                        size: 14,
                      ),
                      onTap: () => _assignRequest(
                        dialogContext,
                        person['id'] as String,
                        person['full_name'] as String? ?? '',
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Vazgeç'),
          ),
        ],
      ),
    );
  }

  Future<void> _assignRequest(
    BuildContext dialogContext,
    String personnelId,
    String personnelName,
  ) async {
    try {
      await _client
          .from('requests')
          .update({'assigned_to': personnelId})
          .eq('id', widget.requestId);

      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Talep $personnelName\'a atandı.')),
      );
      await _loadRequest();
    } on PostgrestException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Talep atanamadı. Lütfen tekrar deneyin.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin.')),
      );
    }
  }

  /// Faz 4: müdür (veya admin), henüz kesin sonuçlanmamış (status='acik')
  /// bir talebi başka birime yönlendirebilir. Düz bir UPDATE bunu yapamaz —
  /// müdürün RLS politikası, yeni satırın department_id'sinin de kendi
  /// birimiyle eşleşmesini şart koşuyor (WITH CHECK) — bu yüzden
  /// `reassign_request_department` security definer RPC'si kullanılıyor.
  Future<void> _onReassignPressed() async {
    setState(() => _isLoadingDepartmentsForReassign = true);
    try {
      final response = await _client
          .from('departments')
          .select('id, name')
          .eq('is_active', true)
          .order('name');
      final currentDepartmentId = _request?['department_id'];
      final departments = List<Map<String, dynamic>>.from(
        response,
      ).where((d) => d['id'] != currentDepartmentId).toList();

      if (!mounted) return;
      _showReassignDialog(departments);
    } on PostgrestException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Birim listesi yüklenemedi. Lütfen tekrar deneyin.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin.')),
      );
    } finally {
      if (mounted) setState(() => _isLoadingDepartmentsForReassign = false);
    }
  }

  void _showReassignDialog(List<Map<String, dynamic>> departments) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Birim Değiştir'),
        content: SizedBox(
          width: double.maxFinite,
          child: departments.isEmpty
              ? const Text('Yönlendirilebilecek başka aktif birim yok.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: departments.length,
                  itemBuilder: (context, index) {
                    final department = departments[index];
                    return ListTile(
                      title: Text(department['name'] as String? ?? ''),
                      onTap: () => _reassignRequest(dialogContext, department['id'] as int),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Vazgeç'),
          ),
        ],
      ),
    );
  }

  Future<void> _reassignRequest(BuildContext dialogContext, int newDepartmentId) async {
    try {
      await _client.rpc(
        'reassign_request_department',
        params: {'p_request_id': widget.requestId, 'p_new_department_id': newDepartmentId},
      );

      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Talep başka birime yönlendirildi.')),
      );
      await _loadRequest();
    } on PostgrestException catch (e) {
      // RPC'nin raise exception ile fırlattığı mesaj zaten anlaşılır Türkçe
      // metin (bkz. reassign_request_department() — "Bu talebi yönlendirme
      // yetkiniz yok.", "Hedef birim pasif, talep yönlendirilemez." vb.).
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin.')),
      );
    }
  }

  void _showResolveDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => _ResolveReportDialog(onSubmit: _submitReport),
    );
  }

  void _showEditReportDialog() {
    final result = _result;
    if (result == null) return;

    showDialog(
      context: context,
      builder: (dialogContext) => _ResolveReportDialog(
        initialText: result['report_text'] as String?,
        onSubmit: (dialogContext, reportText) =>
            _updateReport(dialogContext, result['id'] as String, reportText),
      ),
    );
  }

  Future<void> _submitReport(BuildContext dialogContext, String reportText) async {
    try {
      await _client.from('results').insert({
        'request_id': widget.requestId,
        'report_text': reportText,
        'resolved_by': _client.auth.currentUser!.id,
        'approval_status': 'beklemede',
      });

      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rapor gönderildi, onay bekleniyor.')),
      );
      // requests.status'u 'cozuldu'ya çeken güncelleme veritabanı trigger'ı
      // tarafından otomatik yapılır; burada sadece taze veri çekilir.
      await _loadRequest();
    } on PostgrestException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rapor gönderilemedi. Lütfen tekrar deneyin.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin.')),
      );
    }
  }

  Future<void> _updateReport(
    BuildContext dialogContext,
    String resultId,
    String reportText,
  ) async {
    try {
      // Reddedilen bir rapor yeniden gönderildiğinde onay durumu "beklemede"ye
      // sıfırlanır (approved_by de temizlenir); veritabanı trigger'ı bunu görüp
      // requests.status'u tekrar 'cozuldu'ya çevirir.
      await _client.from('results').update({
        'report_text': reportText,
        'approval_status': 'beklemede',
        'approved_by': null,
      }).eq('id', resultId);

      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rapor güncellendi.')),
      );
      await _loadRequest();
    } on PostgrestException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rapor güncellenemedi. Lütfen tekrar deneyin.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin.')),
      );
    }
  }

  Future<void> _approveReport(String resultId) async {
    try {
      await _client.from('results').update({
        'approval_status': 'onaylandi',
        'approved_by': _client.auth.currentUser!.id,
      }).eq('id', resultId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Talep onaylandı.')),
      );
      await _loadRequest();
    } on PostgrestException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Talep onaylanamadı. Lütfen tekrar deneyin.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin.')),
      );
    }
  }

  Future<void> _rejectReport(String resultId) async {
    try {
      await _client.from('results').update({
        'approval_status': 'reddedildi',
        'approved_by': _client.auth.currentUser!.id,
      }).eq('id', resultId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Talep reddedildi, personele geri döndü.')),
      );
      await _loadRequest();
    } on PostgrestException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Talep reddedilemedi. Lütfen tekrar deneyin.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin.')),
      );
    }
  }

  void _showEditRequestDialog() {
    final request = _request;
    if (request == null) return;

    showDialog(
      context: context,
      builder: (dialogContext) => _EditRequestDialog(
        initialTitle: request['title'] as String? ?? '',
        initialDescription: request['description'] as String? ?? '',
        initialCategory: request['category'] as String? ?? '',
        onSubmit: _updateRequestFields,
      ),
    );
  }

  Future<void> _updateRequestFields(
    BuildContext dialogContext,
    String title,
    String description,
    String category,
  ) async {
    try {
      await _client.from('requests').update({
        'title': title,
        'description': description,
        'category': category,
      }).eq('id', widget.requestId);

      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Talep güncellendi.')),
      );
      await _loadRequest();
    } on PostgrestException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Talep güncellenemedi. Lütfen tekrar deneyin.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin.')),
      );
    }
  }

  void _showCancelConfirmDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Talebi İptal Et'),
        content: const Text('Talebi iptal etmek istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => _cancelRequest(dialogContext),
            child: const Text('Evet, İptal Et'),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelRequest(BuildContext dialogContext) async {
    try {
      await _client.from('requests').update({'status': 'iptal'}).eq('id', widget.requestId);

      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Talep iptal edildi.')),
      );
      await _loadRequest();
    } on PostgrestException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Talep iptal edilemedi. Lütfen tekrar deneyin.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin.')),
      );
    }
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildDetailCard(Map<String, dynamic> request) {
    final status = request['status'] as String? ?? '';
    final requesterType = request['requester_type'] as String? ?? '';
    final department = request['departments'] as Map<String, dynamic>?;
    final assignedTo = request['assigned_to'];
    final resolutionDuration = _formatResolutionDuration(
      request['created_at'] as String?,
      request['resolved_at'] as String?,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildInfoRow('Başlık:', request['title'] as String? ?? ''),
            _buildInfoRow('Açıklama:', request['description'] as String? ?? ''),
            _buildInfoRow('Kategori:', request['category'] as String? ?? ''),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(
                    width: 110,
                    child: Text('Durum:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  StatusBadge(status: status),
                ],
              ),
            ),
            _buildInfoRow('Talep Sahibi:', _requesterTypeLabels[requesterType] ?? requesterType),
            _buildInfoRow('Birim:', department?['name'] as String? ?? ''),
            _buildInfoRow('Atanan:', assignedTo == null ? 'Henüz atanmadı' : 'Atanmış'),
            _buildInfoRow('Oluşturulma:', request['created_at']?.toString() ?? ''),
            if (resolutionDuration != null)
              _buildInfoRow('Çözüm Süresi:', '$resolutionDuration içinde çözüldü'),
            if ((request['reopened_count'] as int? ?? 0) > 0) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  avatar: Icon(Icons.replay, size: 16, color: Colors.purple.shade900),
                  label: Text(
                    'Bu talep daha önce ${request['reopened_count']} kez yeniden açılmıştı.',
                  ),
                  labelStyle: TextStyle(fontSize: 12, color: Colors.purple.shade900),
                  backgroundColor: Colors.purple.shade50,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRatingCard() {
    final myRating = _myRating;
    final ratingValue = myRating?['rating'] as int?;
    final comment = myRating?['comment'] as String?;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Değerlendirme', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (ratingValue != null) ...[
              StarRatingDisplay(rating: ratingValue.toDouble(), showCount: false, size: 20),
              if (comment != null && comment.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(comment, style: const TextStyle(fontStyle: FontStyle.italic)),
              ],
              const SizedBox(height: 12),
            ],
            OutlinedButton.icon(
              onPressed: _showRateDialog,
              icon: const Icon(Icons.star_outline),
              label: Text(ratingValue == null ? 'Talebi Değerlendir' : 'Değerlendirmeni Güncelle'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.history, size: 20),
                const SizedBox(width: 8),
                const Text('Talep Geçmişi', style: TextStyle(fontWeight: FontWeight.bold)),
                if (_isLoadingHistory) ...[
                  const SizedBox(width: 12),
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            if (!_isLoadingHistory && _history.isEmpty)
              const Text('Henüz bir işlem kaydı yok.')
            else
              for (var i = 0; i < _history.length; i++) ...[
                if (i > 0) const Divider(height: 16),
                _buildHistoryTile(_history[i]),
              ],
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryTile(Map<String, dynamic> event) {
    final eventType = event['event_type'] as String;
    final detailRaw = event['detail'];
    final detail = detailRaw is Map ? Map<String, dynamic>.from(detailRaw) : null;
    final detailText = _historyDetailText(eventType, detail);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          _historyEventIcons[eventType] ?? Icons.circle,
          size: 20,
          color: _historyEventColors[eventType] ?? Colors.grey,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_historyEventLabels[eventType] ?? eventType} — ${event['actor_label']}',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              if (detailText != null && detailText.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(detailText, style: const TextStyle(fontSize: 12)),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  _formatHistoryDate(event['created_at'] as String?),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAttachmentsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Ekler:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SizedBox(
              height: 90,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _attachments.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final attachment = _attachments[index];
                  final mediaType = attachment['media_type'] as String? ?? '';
                  final signedUrl = attachment['signed_url'] as String?;
                  final fileName = _originalFileName(attachment['file_url'] as String);
                  final isImage = mediaType == 'image' && signedUrl != null;

                  return GestureDetector(
                    onTap: isImage ? () => _showImagePreview(signedUrl) : null,
                    child: Container(
                      width: 90,
                      height: 90,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      ),
                      child: isImage
                          ? Image.network(signedUrl, fit: BoxFit.cover)
                          : Padding(
                              padding: const EdgeInsets.all(4),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    mediaType == 'video' ? Icons.videocam : Icons.insert_drive_file,
                                    size: 28,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    fileName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.labelSmall,
                                  ),
                                ],
                              ),
                            ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(Map<String, dynamic> result) {
    final approvalStatus = result['approval_status'] as String? ?? '';
    final previouslyRejected = result['previously_rejected'] as bool? ?? false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildInfoRow('Rapor:', result['report_text'] as String? ?? ''),
            _buildInfoRow('Onay Durumu:', _approvalStatusLabels[approvalStatus] ?? approvalStatus),
            // Onay durumu ne olursa olsun (beklemede/onaylandı/reddedildi), bu
            // geçmiş işareti previously_rejected true olduğu sürece görünür.
            if (previouslyRejected) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  label: const Text('Bu rapor daha önce reddedilmiş, yeniden gönderildi.'),
                  labelStyle: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                  backgroundColor: Colors.orange.shade100,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final request = _request;
    final result = _result;
    final canAssign = _role == 'mudur' && request != null && request['assigned_to'] == null;
    final canReassign = (_role == 'mudur' || _role == 'admin') &&
        request != null &&
        request['status'] == 'acik';
    final canResolve = _role == 'personel' &&
        request != null &&
        request['assigned_to'] == _client.auth.currentUser?.id &&
        request['status'] == 'acik' &&
        result == null;
    final canEdit = _role == 'personel' &&
        result != null &&
        result['resolved_by'] == _client.auth.currentUser?.id &&
        (result['approval_status'] == 'beklemede' || result['approval_status'] == 'reddedildi');
    final canApproveOrReject =
        _role == 'mudur' && result != null && result['approval_status'] == 'beklemede';
    final currentUserId = _client.auth.currentUser?.id;
    final isCreator = request != null && request['created_by'] == currentUserId;
    final canEditOrCancelRequest = request != null &&
        isCreator &&
        request['assigned_to'] == null &&
        request['status'] == 'acik';
    final showAssignedWarning = request != null && isCreator && request['assigned_to'] != null;
    final canRate = request != null && isCreator && request['status'] == 'onaylandi';
    final canReopen = request != null &&
        request['status'] == 'onaylandi' &&
        (isCreator || _role == 'admin');
    final showHistory = request != null && ['personel', 'mudur', 'admin'].contains(_role);

    return Scaffold(
      appBar: AppBar(title: const Text('Talep Detayı')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : request == null
              ? const Center(child: Text('Talep bulunamadı.'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildDetailCard(request),
                      if (_attachments.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _buildAttachmentsCard(),
                      ],
                      if (result != null) ...[
                        const SizedBox(height: 16),
                        _buildResultCard(result),
                      ],
                      if (canRate) ...[
                        const SizedBox(height: 16),
                        _buildRatingCard(),
                      ],
                      if (showHistory) ...[
                        const SizedBox(height: 16),
                        _buildHistoryCard(),
                      ],
                      if (canAssign) ...[
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _isLoadingPersonnel ? null : _onAssignPressed,
                          child: _isLoadingPersonnel
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Ata'),
                        ),
                      ],
                      if (canReassign) ...[
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: _isLoadingDepartmentsForReassign
                              ? null
                              : _onReassignPressed,
                          child: _isLoadingDepartmentsForReassign
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Birim Değiştir'),
                        ),
                      ],
                      if (canResolve) ...[
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _showResolveDialog,
                          child: const Text('Çözümle'),
                        ),
                      ],
                      if (canEdit) ...[
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _showEditReportDialog,
                          child: const Text('Düzenle'),
                        ),
                      ],
                      if (canApproveOrReject) ...[
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton(
                                onPressed: () => _approveReport(result['id'] as String),
                                child: const Text('Onayla'),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                onPressed: () => _rejectReport(result['id'] as String),
                                child: const Text('Reddet'),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (canReopen) ...[
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _isReopening ? null : _showReopenConfirmDialog,
                          icon: const Icon(Icons.replay),
                          label: const Text('Talebi Yeniden Aç'),
                        ),
                      ],
                      if (canEditOrCancelRequest) ...[
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton(
                                onPressed: _showEditRequestDialog,
                                child: const Text('Düzenle'),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                onPressed: _showCancelConfirmDialog,
                                child: const Text('İptal Et'),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (showAssignedWarning) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            border: Border.all(color: Colors.orange.shade200),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Talebiniz ilgili birim personeline atanmıştır, şu an talepte '
                            'değişiklik yapılamaz.',
                            style: TextStyle(color: Colors.orange.shade900),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }
}

/// "Talebi Değerlendir" butonuyla açılan, 1-5 yıldız + opsiyonel yorum alan
/// dialog (Faz 6, 2026-07-23). Diğer dialoglardaki (`_ResolveReportDialog`)
/// desenle aynı: kendi state'ini (seçilen yıldız sayısı, gönderim durumu)
/// yönetir.
class _RateRequestDialog extends StatefulWidget {
  final int initialRating;
  final String? initialComment;
  final Future<void> Function(BuildContext dialogContext, int rating, String comment) onSubmit;

  const _RateRequestDialog({
    required this.initialRating,
    this.initialComment,
    required this.onSubmit,
  });

  @override
  State<_RateRequestDialog> createState() => _RateRequestDialogState();
}

class _RateRequestDialogState extends State<_RateRequestDialog> {
  late int _rating = widget.initialRating;
  late final _commentController = TextEditingController(text: widget.initialComment);
  bool _isSubmitting = false;
  String? _errorText;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating < 1) {
      setState(() => _errorText = 'Lütfen 1-5 arası bir puan seçin.');
      return;
    }
    setState(() {
      _errorText = null;
      _isSubmitting = true;
    });
    await widget.onSubmit(context, _rating, _commentController.text.trim());
    if (mounted) setState(() => _isSubmitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Talebi Değerlendir'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StarRatingInput(rating: _rating, onChanged: (value) => setState(() => _rating = value)),
          if (_errorText != null) ...[
            const SizedBox(height: 4),
            Text(_errorText!, style: const TextStyle(color: Colors.red, fontSize: 12)),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _commentController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Yorumunuz (opsiyonel)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Gönder'),
        ),
      ],
    );
  }
}

/// "Çözümle" butonuyla açılan, çözüm raporu metnini alan dialog. Kendi
/// içinde form/submit durumunu yönettiği için (validasyon, gönderim sırasında
/// buton kilitlenmesi) ayrı bir StatefulWidget olarak tutulur — diğer
/// dialoglardaki (_showAssignDialog) gibi stateless bir builder yeterli
/// olmazdı.
class _ResolveReportDialog extends StatefulWidget {
  final String? initialText;
  final Future<void> Function(BuildContext dialogContext, String reportText) onSubmit;

  const _ResolveReportDialog({this.initialText, required this.onSubmit});

  @override
  State<_ResolveReportDialog> createState() => _ResolveReportDialogState();
}

class _ResolveReportDialogState extends State<_ResolveReportDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _reportController = TextEditingController(text: widget.initialText);
  bool _isSubmitting = false;

  @override
  void dispose() {
    _reportController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    await widget.onSubmit(context, _reportController.text.trim());
    if (mounted) setState(() => _isSubmitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Çözüm Raporu'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _reportController,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'Rapor Metni'),
          validator: (value) =>
              (value == null || value.trim().isEmpty) ? 'Rapor metni girin' : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Gönder'),
        ),
      ],
    );
  }
}

/// "Düzenle" (talep sahibinin kendi talebini düzenlemesi) butonuyla açılan,
/// title/description/category alanlarını mevcut değerlerle önceden dolu
/// getiren dialog (bkz. request_create_screen.dart'taki form alanlarıyla
/// aynı yapı).
class _EditRequestDialog extends StatefulWidget {
  final String initialTitle;
  final String initialDescription;
  final String initialCategory;
  final Future<void> Function(
    BuildContext dialogContext,
    String title,
    String description,
    String category,
  ) onSubmit;

  const _EditRequestDialog({
    required this.initialTitle,
    required this.initialDescription,
    required this.initialCategory,
    required this.onSubmit,
  });

  @override
  State<_EditRequestDialog> createState() => _EditRequestDialogState();
}

class _EditRequestDialogState extends State<_EditRequestDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _titleController = TextEditingController(text: widget.initialTitle);
  late final _descriptionController = TextEditingController(text: widget.initialDescription);
  late final _categoryController = TextEditingController(text: widget.initialCategory);
  bool _isSubmitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    await widget.onSubmit(
      context,
      _titleController.text.trim(),
      _descriptionController.text.trim(),
      _categoryController.text.trim(),
    );
    if (mounted) setState(() => _isSubmitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Talebi Düzenle'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Başlık'),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'Başlık girin' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Açıklama'),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'Açıklama girin' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _categoryController,
                decoration: const InputDecoration(labelText: 'Kategori'),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'Kategori girin' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Gönder'),
        ),
      ],
    );
  }
}

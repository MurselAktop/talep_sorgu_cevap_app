import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// `requests.status` ham değerlerinin Türkçe karşılıkları (bkz. CLAUDE.md —
/// Talep durum akışı). Faz 3'te request_list_screen.dart ve
/// my_requests_screen.dart'taki özel kopyaların yerini aldı — projedeki
/// ilk paylaşılan widget dosyası bu, `_requesterTypeLabels` ve
/// `_buildRequestCard` bilinçli olarak burada değil (ilgisiz, önceden var
/// olan bir tekrar, bu görevin kapsamı dışında).
const Map<String, String> statusLabels = {
  'acik': 'Açık',
  'cozuldu': 'Çözüldü (Onay Bekliyor)',
  'onaylandi': 'Onaylandı',
  'reddedildi': 'Reddedildi',
  'iptal': 'İptal Edildi',
};

/// PostgREST'in `.or()` grameri `,`/`(`/`)`/`"`/`\` karakterlerini ayırıcı
/// olarak kullanır ve bunları KENDİSİ escape etmez (postgrest paketinin
/// kaynağında doğrulandı) — kullanıcı arama metnini bu filtreye koymadan
/// önce escape etmek bize ait bir sorumluluk.
String _escapeFilterValue(String raw) =>
    raw.replaceAll('\\', '\\\\').replaceAll('"', '\\"');

/// Talep listelerinde (Gelen Talepler / Taleplerim) arama + filtreleme
/// durumunu tutan değişmez değer sınıfı. Faz 3 kararı: server-side
/// filtreleme (RLS zaten üst sınırı belirliyor, bu filtreler onun üzerine
/// ekstra AND koşulu ekliyor — mevcut department_id/assigned_to/created_by
/// client filtreleriyle aynı prensip, bkz. CLAUDE.md).
class RequestFilters {
  final String searchText;
  final String? status;
  final String category;
  final DateTime? dateFrom;
  final DateTime? dateTo;

  const RequestFilters({
    this.searchText = '',
    this.status,
    this.category = '',
    this.dateFrom,
    this.dateTo,
  });

  factory RequestFilters.empty() => const RequestFilters();

  bool get isActive =>
      searchText.trim().isNotEmpty ||
      status != null ||
      category.trim().isNotEmpty ||
      dateFrom != null ||
      dateTo != null;

  RequestFilters copyWith({String? searchText}) {
    return RequestFilters(
      searchText: searchText ?? this.searchText,
      status: status,
      category: category,
      dateFrom: dateFrom,
      dateTo: dateTo,
    );
  }

  /// Arama/filtre koşullarını sırayla sorguya ekler. `.or()` bir build'de
  /// EN FAZLA bir kez çağrılır (burada sadece başlık+açıklama araması için)
  /// — birden fazla `.or()` çağrısı tek bir OR grubunda birleşmez, ayrı
  /// `or=` parametreleri üretir.
  PostgrestFilterBuilder<T> applyTo<T>(PostgrestFilterBuilder<T> query) {
    var result = query;

    final search = searchText.trim();
    if (search.isNotEmpty) {
      final v = _escapeFilterValue(search);
      result = result.or('title.ilike."%$v%",description.ilike."%$v%"');
    }

    final categoryValue = category.trim();
    if (categoryValue.isNotEmpty) {
      result = result.ilike(
        'category',
        '%${_escapeFilterValue(categoryValue)}%',
      );
    }

    if (status != null) {
      result = result.eq('status', status!);
    }

    if (dateFrom != null) {
      final from = DateTime(dateFrom!.year, dateFrom!.month, dateFrom!.day);
      result = result.gte('created_at', from.toUtc().toIso8601String());
    }
    if (dateTo != null) {
      // Üst sınır her zaman DIŞLAYICI: seçilen bitiş gününün ertesi günü
      // başlangıcı — off-by-one/saat dilimi hatasını önler, o günün tüm
      // saatleri dahil olur.
      final toExclusive = DateTime(
        dateTo!.year,
        dateTo!.month,
        dateTo!.day,
      ).add(const Duration(days: 1));
      result = result.lt('created_at', toExclusive.toUtc().toIso8601String());
    }

    return result;
  }
}

/// `RequestFilters`'ın durum/kategori/tarih aralığı kısmını düzenleyen modal
/// bottom sheet. Arama metni burada YOK — o, çağıran ekranda ayrı, her
/// zaman görünür bir alan; bu yüzden "Temizle" de sadece bu sheet'in kendi
/// alanlarını sıfırlar, arama metnine dokunmaz. `showModalBottomSheet` ile
/// açılır; "Uygula"/"Temizle" basılınca yeni `RequestFilters`'ı
/// `Navigator.pop` ile döndürür, geri tuşu/dışarı tıklamada `null` döner.
class RequestFilterSheet extends StatefulWidget {
  final RequestFilters initialFilters;

  const RequestFilterSheet({super.key, required this.initialFilters});

  @override
  State<RequestFilterSheet> createState() => _RequestFilterSheetState();
}

class _RequestFilterSheetState extends State<RequestFilterSheet> {
  late String? _status;
  late final TextEditingController _categoryController;
  DateTime? _dateFrom;
  DateTime? _dateTo;

  @override
  void initState() {
    super.initState();
    _status = widget.initialFilters.status;
    _categoryController = TextEditingController(
      text: widget.initialFilters.category,
    );
    _dateFrom = widget.initialFilters.dateFrom;
    _dateTo = widget.initialFilters.dateTo;
  }

  @override
  void dispose() {
    _categoryController.dispose();
    super.dispose();
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: (_dateFrom != null && _dateTo != null)
          ? DateTimeRange(start: _dateFrom!, end: _dateTo!)
          : null,
    );
    if (picked != null) {
      setState(() {
        _dateFrom = picked.start;
        _dateTo = picked.end;
      });
    }
  }

  String _dateRangeLabel() {
    if (_dateFrom == null || _dateTo == null) return 'Tarih aralığı seçilmedi';
    String two(int n) => n.toString().padLeft(2, '0');
    String fmt(DateTime d) => '${two(d.day)}.${two(d.month)}.${d.year}';
    return '${fmt(_dateFrom!)} — ${fmt(_dateTo!)}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Filtrele', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          DropdownButtonFormField<String?>(
            initialValue: _status,
            decoration: const InputDecoration(labelText: 'Durum'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Tümü')),
              for (final entry in statusLabels.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (value) => setState(() => _status = value),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _categoryController,
            decoration: const InputDecoration(labelText: 'Kategori'),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: Text(_dateRangeLabel())),
              TextButton(
                onPressed: _pickDateRange,
                child: const Text('Tarih Aralığı Seç'),
              ),
              if (_dateFrom != null || _dateTo != null)
                IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: 'Tarih aralığını temizle',
                  onPressed: () => setState(() {
                    _dateFrom = null;
                    _dateTo = null;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(
                    RequestFilters(searchText: widget.initialFilters.searchText),
                  ),
                  child: const Text('Temizle'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(
                    RequestFilters(
                      searchText: widget.initialFilters.searchText,
                      status: _status,
                      category: _categoryController.text,
                      dateFrom: _dateFrom,
                      dateTo: _dateTo,
                    ),
                  ),
                  child: const Text('Uygula'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

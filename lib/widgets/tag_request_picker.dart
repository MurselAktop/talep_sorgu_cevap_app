import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';
import 'status_badge.dart';

/// DM mesajına bir talep "etiketlemek" için açılan arama listesi (Faz 7,
/// 2026-07-23). Bilinçli olarak `request_list_screen.dart`/
/// `my_requests_screen.dart`'ın aksine EK bir rol filtresi UYGULAMIYOR —
/// oradaki ekranlar RLS'in izin verdiği kümenin bir ALT kümesini
/// göstermek zorunda (bkz. o dosyalardaki gerekçe), ama burada tam tersine
/// kullanıcının bağlantısı olan HER talebi (kendi açtığı + atanan/birimi +
/// admin'de hepsi) etiketleyebilmesi isteniyor — yani RLS'in izin verdiği
/// EN GENİŞ küme zaten doğru sonuç, ek filtreye gerek yok.
Future<Map<String, dynamic>?> showTagRequestPicker(BuildContext context) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _TagRequestPickerSheet(),
  );
}

class _TagRequestPickerSheet extends StatefulWidget {
  const _TagRequestPickerSheet();

  @override
  State<_TagRequestPickerSheet> createState() => _TagRequestPickerSheetState();
}

class _TagRequestPickerSheetState extends State<_TagRequestPickerSheet> {
  static SupabaseClient get _client => SupabaseService.client;

  final _searchController = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _requests = [];
  bool _isLoading = true;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({String? searchText}) async {
    setState(() {
      _isLoading = true;
      _errorText = null;
    });
    try {
      var query = _client.from('requests').select('id, title, status, category');
      final text = searchText?.trim();
      if (text != null && text.isNotEmpty) {
        final escaped = text.replaceAll('\\', '\\\\').replaceAll(',', '\\,').replaceAll('(', '\\(').replaceAll(')', '\\)');
        query = query.or('title.ilike."%$escaped%",category.ilike."%$escaped%"');
      }
      final rows = await query.order('created_at', ascending: false).limit(50);
      if (!mounted) return;
      setState(() => _requests = List<Map<String, dynamic>>.from(rows));
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorText = 'Talepler yüklenemedi. Lütfen tekrar deneyin.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _load(searchText: value));
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Bir Talep Etiketle',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: const InputDecoration(
                  hintText: 'Talep başlığı veya kategori ara...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorText != null
                      ? Center(child: Text(_errorText!))
                      : _requests.isEmpty
                          ? const Center(child: Text('Eşleşen talep bulunamadı.'))
                          : ListView.builder(
                              controller: scrollController,
                              itemCount: _requests.length,
                              itemBuilder: (context, index) {
                                final request = _requests[index];
                                return ListTile(
                                  title: Text(
                                    request['title'] as String? ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(request['category'] as String? ?? ''),
                                  trailing: StatusBadge(status: request['status'] as String? ?? ''),
                                  onTap: () => Navigator.of(context).pop(request),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

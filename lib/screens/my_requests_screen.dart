import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';
import '../widgets/app_nav_route.dart';
import '../widgets/navigation_shell.dart';
import '../widgets/request_filters.dart';
import '../widgets/status_badge.dart';
import 'request_detail_screen.dart';

/// `requests.requester_type` ham değerlerinin Türkçe karşılıkları.
const Map<String, String> _requesterTypeLabels = {
  'vatandas': 'Vatandaş',
  'anonim': 'Anonim',
  'personel': 'Personel',
};

/// Giriş yapmış herhangi bir kullanıcının (vatandaş/personel/müdür/admin)
/// kendi açtığı talepleri listelediği ekran. `eq('created_by', ...)` filtresi
/// burada bilinçli olarak eklenir: personel/müdür/admin için RLS, birim
/// eşleşmesi VEYA kendi açtığı talep kurallarını OR ile birleştirdiğinden,
/// filtresiz bir sorgu request_list_screen.dart'taki (Gelen Talepler) ile
/// aynı geniş kümeyi döndürür. Bu filtre, RLS'in izin verdiği kümenin
/// yalnızca "kendi talebim" alt kümesini seçer; güvenlik sınırı hâlâ RLS
/// tarafından belirlenir (bkz. CLAUDE.md — RLS Planı).
class MyRequestsScreen extends StatefulWidget {
  const MyRequestsScreen({super.key});

  @override
  State<MyRequestsScreen> createState() => _MyRequestsScreenState();
}

class _MyRequestsScreenState extends State<MyRequestsScreen> {
  static SupabaseClient get _client => SupabaseService.client;

  List<Map<String, dynamic>> _requests = [];
  bool _isLoading = true;
  RequestFilters _filters = RequestFilters.empty();
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRequests() async {
    try {
      var query = _client
          .from('requests')
          .select('*, departments(name)')
          .eq('created_by', _client.auth.currentUser!.id);
      // Faz 3: arama/filtreler de aynı ekran-daraltma prensibiyle,
      // created_by filtresinden SONRA order()'dan ÖNCE ekleniyor (server-side).
      query = _filters.applyTo(query);
      final response = await query.order('created_at', ascending: false);
      setState(() => _requests = List<Map<String, dynamic>>.from(response));
    } on PostgrestException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Talepler yüklenemedi. Lütfen tekrar deneyin.')),
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

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      setState(() {
        _filters = _filters.copyWith(searchText: value);
        _isLoading = true;
      });
      _loadRequests();
    });
  }

  Future<void> _openFilterSheet() async {
    final result = await showModalBottomSheet<RequestFilters>(
      context: context,
      isScrollControlled: true,
      builder: (_) => RequestFilterSheet(initialFilters: _filters),
    );
    if (result == null || !mounted) return;
    setState(() {
      _filters = result;
      _isLoading = true;
    });
    _loadRequests();
  }

  Widget _buildRequestCard(Map<String, dynamic> request) {
    final status = request['status'] as String? ?? '';
    final requesterType = request['requester_type'] as String? ?? '';
    final department = request['departments'] as Map<String, dynamic>?;
    final assignedTo = request['assigned_to'];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        title: Text(request['title'] as String? ?? ''),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Kategori: ${request['category'] as String? ?? ''}'),
            Text('Talep Sahibi: ${_requesterTypeLabels[requesterType] ?? requesterType}'),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [const Text('Durum: '), StatusBadge(status: status)],
              ),
            ),
            Text('Birim: ${department?['name'] as String? ?? ''}'),
            Text('Oluşturulma: ${request['created_at']?.toString() ?? ''}'),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Chip(
                label: Text(assignedTo == null ? 'Atanmadı' : 'Atanmış'),
                labelStyle: TextStyle(
                  fontSize: 12,
                  color: assignedTo == null ? Colors.orange.shade900 : Colors.green.shade900,
                ),
                backgroundColor: assignedTo == null ? Colors.orange.shade100 : Colors.green.shade100,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RequestDetailScreen(requestId: request['id'] as String),
            ),
          );
          if (!mounted) return;
          await _loadRequests();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return NavigationShell(
      currentRoute: AppNavRoute.myRequests,
      title: 'Taleplerim',
      actions: [
        IconButton(
          icon: Badge(
            isLabelVisible: _filters.isActive,
            child: const Icon(Icons.tune),
          ),
          tooltip: 'Filtrele',
          onPressed: _openFilterSheet,
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Yenile',
          onPressed: _loadRequests,
        ),
      ],
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Başlık veya açıklamada ara...',
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: 'Aramayı temizle',
                  onPressed: () {
                    _searchController.clear();
                    _onSearchChanged('');
                  },
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _requests.isEmpty
                    ? const Center(child: Text('Görüntülenecek talep bulunamadı.'))
                    : RefreshIndicator(
                        onRefresh: _loadRequests,
                        child: ListView.builder(
                          itemCount: _requests.length,
                          itemBuilder: (context, index) =>
                              _buildRequestCard(_requests[index]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

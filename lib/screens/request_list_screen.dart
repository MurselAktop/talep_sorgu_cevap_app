import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';
import '../widgets/request_filters.dart';
import 'request_detail_screen.dart';

/// `requests.requester_type` ham değerlerinin Türkçe karşılıkları.
const Map<String, String> _requesterTypeLabels = {
  'vatandas': 'Vatandaş',
  'anonim': 'Anonim',
  'personel': 'Personel',
};

/// Personel/müdür/admin'in "bana atanan / birimimin talepleri"ni listelediği
/// ekran. RLS'teki "açan kişi kendi talebini görebilir" kuralı herkese
/// uygulandığından, kullanıcının kendi oluşturduğu bir talep filtresiz bir
/// sorguda da görünür ve bu ekranın amacıyla (atanan/birim talepleri) karışır.
/// Bu yüzden role'e göre istemci tarafında ek bir filtre uygulanır: personel
/// için `assigned_to = kendisi`, müdür için `department_id = kendi birimi`,
/// admin için ek filtre yok (tüm talepler). Bu filtreler, RLS'in izin verdiği
/// daha geniş kümenin yalnızca bu ekrana özgü alt kümesini seçer; güvenlik
/// sınırı hâlâ RLS tarafından belirlenir (bkz. CLAUDE.md — RLS Planı; aynı
/// mantık my_requests_screen.dart'ta da kullanılıyor).
class RequestListScreen extends StatefulWidget {
  const RequestListScreen({super.key});

  @override
  State<RequestListScreen> createState() => _RequestListScreenState();
}

class _RequestListScreenState extends State<RequestListScreen> {
  static SupabaseClient get _client => SupabaseService.client;

  List<Map<String, dynamic>> _requests = [];
  bool _isLoading = true;
  String? _role;
  bool _showUnassignedOnly = false;
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
      final userId = _client.auth.currentUser!.id;
      final profile = await _client
          .from('users')
          .select('role, department_id')
          .eq('id', userId)
          .single();
      final role = profile['role'] as String;

      var query = _client.from('requests').select('*, departments(name)');
      if (role == 'mudur') {
        query = query.eq('department_id', profile['department_id']);
      } else if (role == 'personel') {
        query = query.eq('assigned_to', userId);
      }
      // role == 'admin' ise ek filtre uygulanmaz; RLS zaten tüm talepleri döndürür.

      // "Sadece Atanmamışları Göster" filtresi sadece müdür/admin için gösterilir
      // (bkz. build metodu); personel zaten sadece kendi atanan taleplerini görür.
      if (_showUnassignedOnly && (role == 'mudur' || role == 'admin')) {
        query = query.isFilter('assigned_to', null);
      }

      // Faz 3: arama/filtreler de aynı ekran-daraltma prensibiyle, rol
      // bazlı filtrelerden SONRA order()'dan ÖNCE ekleniyor (server-side).
      query = _filters.applyTo(query);

      final response = await query.order('created_at', ascending: false);
      setState(() {
        _requests = List<Map<String, dynamic>>.from(response);
        _role = role;
      });
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

  void _onToggleUnassignedFilter(bool value) {
    setState(() {
      _showUnassignedOnly = value;
      _isLoading = true;
    });
    _loadRequests();
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
            Text('Durum: ${statusLabels[status] ?? status}'),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gelen Talepler'),
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
      ),
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
          if (_role == 'mudur' || _role == 'admin')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilterChip(
                  label: const Text('Sadece Atanmamışları Göster'),
                  selected: _showUnassignedOnly,
                  onSelected: _isLoading ? null : _onToggleUnassignedFilter,
                ),
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
                          itemBuilder: (context, index) => _buildRequestCard(_requests[index]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

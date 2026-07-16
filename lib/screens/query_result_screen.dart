import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';

/// `requests.status` ham değerlerinin kullanıcıya gösterilecek Türkçe
/// karşılıkları (bkz. CLAUDE.md — Talep durum akışı).
const Map<String, String> _statusLabels = {
  'acik': 'Açık',
  'cozuldu': 'Çözüldü (Onay Bekliyor)',
  'onaylandi': 'Onaylandı',
  'reddedildi': 'Reddedildi',
  'iptal': 'İptal Edildi',
};

/// Anonim vatandaşın, kayıt sırasında aldığı `access_token` ile hesap
/// açmadan talebinin durumunu sorguladığı ekran (bkz. CLAUDE.md — hibrit
/// vatandaş erişimi modeli).
class QueryResultScreen extends StatefulWidget {
  const QueryResultScreen({super.key});

  @override
  State<QueryResultScreen> createState() => _QueryResultScreenState();
}

class _QueryResultScreenState extends State<QueryResultScreen> {
  static SupabaseClient get _client => SupabaseService.client;

  final _formKey = GlobalKey<FormState>();
  final _tokenController = TextEditingController();

  bool _isQuerying = false;
  Map<String, dynamic>? _result;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _query() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isQuerying = true;
      _result = null;
    });
    try {
      final response = await _client.rpc('get_request_by_token', params: {
        'p_access_token': _tokenController.text.trim().toUpperCase(),
      }) as List;

      if (!mounted) return;
      if (response.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bu koda ait bir talep bulunamadı. Lütfen kodu kontrol edin.')),
        );
        return;
      }

      setState(() => _result = Map<String, dynamic>.from(response.first as Map));
    } on PostgrestException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sorgulama yapılamadı. Lütfen tekrar deneyin.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin.')),
      );
    } finally {
      if (mounted) setState(() => _isQuerying = false);
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

  Widget _buildResultCard(Map<String, dynamic> result) {
    final status = result['status'] as String? ?? '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildInfoRow('Başlık:', result['title'] as String? ?? ''),
            _buildInfoRow('Açıklama:', result['description'] as String? ?? ''),
            _buildInfoRow('Kategori:', result['category'] as String? ?? ''),
            _buildInfoRow('Durum:', _statusLabels[status] ?? status),
            _buildInfoRow('Birim:', result['department_name'] as String? ?? ''),
            _buildInfoRow('Oluşturulma:', result['created_at']?.toString() ?? ''),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Sonucu Sorgula')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _tokenController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Talep Kodu'),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty) ? 'Talep kodu girin' : null,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _isQuerying ? null : _query,
                    child: _isQuerying
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Sorgula'),
                  ),
                  if (result != null) ...[
                    const SizedBox(height: 24),
                    _buildResultCard(result),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

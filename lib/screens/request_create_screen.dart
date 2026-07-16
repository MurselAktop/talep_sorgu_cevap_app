import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';

/// Talep/şikâyet oluşturma ekranı. Hem anonim (hesapsız), hem hesaplı
/// vatandaş, hem de personel buradan talep açabilir. `requester_type` ve
/// `created_by` kullanıcıya hiç sorulmaz; oturum durumuna ve public.users'daki
/// role'e bakılarak otomatik belirlenir (bkz. CLAUDE.md — hibrit vatandaş
/// erişimi modeli). `id`, `created_at`, `status`, `assigned_to`,
/// `access_token` alanlarına dokunulmaz; hepsinin veritabanında otomatik
/// varsayılanı vardır.
class RequestCreateScreen extends StatefulWidget {
  const RequestCreateScreen({super.key});

  @override
  State<RequestCreateScreen> createState() => _RequestCreateScreenState();
}

class _RequestCreateScreenState extends State<RequestCreateScreen> {
  static SupabaseClient get _client => SupabaseService.client;

  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _categoryController = TextEditingController();

  List<Map<String, dynamic>> _departments = [];
  int? _selectedDepartmentId;
  bool _isLoadingDepartments = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadDepartments();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  Future<void> _loadDepartments() async {
    try {
      final response = await _client.from('departments').select('id, name').order('name');
      setState(() => _departments = List<Map<String, dynamic>>.from(response));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Birimler yüklenemedi. Lütfen sayfayı yenileyin.')),
      );
    } finally {
      if (mounted) setState(() => _isLoadingDepartments = false);
    }
  }

  /// Giriş yapılmamışsa 'anonim'; giriş yapılmışsa public.users'daki role'e
  /// göre 'vatandas' ya da 'personel' (personel/müdür/admin) döner.
  Future<String> _resolveRequesterType(String? currentUserId) async {
    if (currentUserId == null) return 'anonim';

    final profile = await _client
        .from('users')
        .select('role')
        .eq('id', currentUserId)
        .single();
    final role = profile['role'] as String;
    return role == 'vatandas' ? 'vatandas' : 'personel';
  }

  Future<void> _submit() async {
    if (_selectedDepartmentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen bir birim seçin.')),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      final currentUserId = _client.auth.currentUser?.id;
      final requesterType = await _resolveRequesterType(currentUserId);

      final accessToken = await _client.rpc('create_request', params: {
        'p_title': _titleController.text.trim(),
        'p_description': _descriptionController.text.trim(),
        'p_category': _categoryController.text.trim(),
        'p_department_id': _selectedDepartmentId,
        'p_requester_type': requesterType,
        'p_created_by': currentUserId,
      }) as String;

      if (!mounted) return;
      _showAccessTokenDialog(accessToken, requesterType);
    } on PostgrestException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Talep oluşturulamadı. Lütfen tekrar deneyin.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin.')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showAccessTokenDialog(String accessToken, String requesterType) {
    final description = requesterType == 'anonim'
        ? 'Bu kodu saklayın — talebinizin durumunu ileride bu kodla, hesap açmadan sorgulayabilirsiniz.'
        : 'Talebiniz oluşturuldu. Bu kod, talebinizin referans numarasıdır.';

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Talep Oluşturuldu'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(description),
            const SizedBox(height: 16),
            SelectableText(
              accessToken,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 2),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: accessToken));
              if (!dialogContext.mounted) return;
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                const SnackBar(content: Text('Kod kopyalandı.')),
              );
            },
            icon: const Icon(Icons.copy),
            label: const Text('Kopyala'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Talep Oluştur')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
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
                  const SizedBox(height: 16),
                  _isLoadingDepartments
                      ? const Center(child: CircularProgressIndicator())
                      : DropdownButtonFormField<int>(
                          initialValue: _selectedDepartmentId,
                          decoration: const InputDecoration(labelText: 'Birim'),
                          items: _departments
                              .map(
                                (department) => DropdownMenuItem<int>(
                                  value: department['id'] as int,
                                  child: Text(department['name'] as String),
                                ),
                              )
                              .toList(),
                          onChanged: (value) => setState(() => _selectedDepartmentId = value),
                        ),
                  const SizedBox(height: 24),
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
              ),
            ),
          ),
        ),
      ),
    );
  }
}

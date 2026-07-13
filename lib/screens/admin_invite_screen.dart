import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';

/// Admin'in personel/müdür/admin daveti oluşturmasını sağlayan ekran.
/// Davet kodu (`code`) veritabanında `generate_invite_code()` default'uyla
/// otomatik üretildiği için burada elle üretilmiyor; sadece department_id,
/// role ve created_by gönderilip veritabanının ürettiği kod geri okunuyor.
class AdminInviteScreen extends StatefulWidget {
  const AdminInviteScreen({super.key});

  @override
  State<AdminInviteScreen> createState() => _AdminInviteScreenState();
}

/// Ekranda gösterilen rol etiketleri ile veritabanına gidecek gerçek
/// değerler farklı olduğu için (Türkçe-karaktersiz, küçük harf kuralı),
/// bu eşleşme burada sabit tutulur.
const Map<String, String> _roleLabels = {
  'personel': 'Personel',
  'mudur': 'Müdür',
  'admin': 'Admin',
};

class _AdminInviteScreenState extends State<AdminInviteScreen> {
  static SupabaseClient get _client => SupabaseService.client;

  List<Map<String, dynamic>> _departments = [];
  List<Map<String, dynamic>> _invites = [];
  int? _selectedDepartmentId;
  String? _selectedRole;
  bool _isLoadingDepartments = true;
  bool _isLoadingInvites = true;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _loadDepartments();
    _loadInvites();
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

  Future<void> _loadInvites() async {
    try {
      final response = await _client
          .from('personnel_invites')
          .select('code, role, used, created_at')
          .order('created_at', ascending: false);
      setState(() => _invites = List<Map<String, dynamic>>.from(response));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Davet kodları yüklenemedi. Lütfen sayfayı yenileyin.')),
      );
    } finally {
      if (mounted) setState(() => _isLoadingInvites = false);
    }
  }

  Future<void> _createInvite() async {
    if (_selectedDepartmentId == null || _selectedRole == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen bir birim ve rol seçin.')),
      );
      return;
    }

    setState(() => _isCreating = true);
    try {
      final currentUserId = _client.auth.currentUser?.id;
      final result = await _client
          .from('personnel_invites')
          .insert({
            'department_id': _selectedDepartmentId,
            'role': _selectedRole,
            'created_by': currentUserId,
          })
          .select('code')
          .single();

      final code = result['code'] as String;
      await _loadInvites();

      if (!mounted) return;
      _showInviteCodeDialog(code);
    } on PostgrestException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Davet kodu oluşturulamadı. Lütfen tekrar deneyin.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin.')),
      );
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  void _showInviteCodeDialog(String code) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Davet Kodu Oluşturuldu'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Bu kodu ilgili personele iletin:'),
            const SizedBox(height: 16),
            SelectableText(
              code,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 2),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
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
      appBar: AppBar(title: const Text('Personel Daveti Oluştur')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedRole,
              decoration: const InputDecoration(labelText: 'Rol'),
              items: _roleLabels.entries
                  .map(
                    (entry) => DropdownMenuItem<String>(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _selectedRole = value),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isCreating ? null : _createInvite,
              child: _isCreating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Davet Kodu Oluştur'),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const Text('Oluşturulmuş Davet Kodları', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
              child: _isLoadingInvites
                  ? const Center(child: CircularProgressIndicator())
                  : _invites.isEmpty
                      ? const Center(child: Text('Henüz davet kodu oluşturulmadı.'))
                      : ListView.builder(
                          itemCount: _invites.length,
                          itemBuilder: (context, index) {
                            final invite = _invites[index];
                            final used = invite['used'] as bool;
                            final role = invite['role'] as String;
                            return ListTile(
                              title: Text(
                                invite['code'] as String,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  decoration: used ? TextDecoration.lineThrough : null,
                                  color: used ? Colors.grey : null,
                                ),
                              ),
                              subtitle: Text(_roleLabels[role] ?? role),
                              trailing: Text(
                                used ? 'Kullanıldı' : 'Kullanılmadı',
                                style: TextStyle(color: used ? Colors.grey : Colors.green),
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
}

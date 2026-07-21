import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';

/// Admin'in birim (departman) ekleyip düzenlediği, sil yerine
/// pasifleştirdiği ekran (Faz 4). `departments.is_active` false olan bir
/// birim, yeni talep/personel daveti dropdown'larında görünmez (bkz.
/// request_create_screen.dart, admin_invite_screen.dart) ama geçmiş
/// taleplerdeki adı görünmeye devam eder — bu yüzden bu ekran, dropdown'ların
/// aksine, hem aktif hem pasif birimleri listeler (admin ikisini de
/// yönetebilmeli).
class AdminDepartmentScreen extends StatefulWidget {
  const AdminDepartmentScreen({super.key});

  @override
  State<AdminDepartmentScreen> createState() => _AdminDepartmentScreenState();
}

class _AdminDepartmentScreenState extends State<AdminDepartmentScreen> {
  static SupabaseClient get _client => SupabaseService.client;

  final _nameController = TextEditingController();
  List<Map<String, dynamic>> _departments = [];
  bool _isLoadingDepartments = true;
  bool _isCreating = false;
  String? _nameErrorText;

  @override
  void initState() {
    super.initState();
    _loadDepartments();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadDepartments() async {
    try {
      final response = await _client
          .from('departments')
          .select('id, name, is_active')
          .order('name');
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

  /// `departments_name_key` UNIQUE ihlalini Türkçe mesaja çevirir; diğer
  /// hataları olduğu gibi bırakır (generic SnackBar ile ele alınır).
  String? _describeSaveError(Object error) {
    if (error is PostgrestException &&
        (error.message.contains('departments_name_key') ||
            error.message.toLowerCase().contains('duplicate key'))) {
      return 'Bu isimde bir birim zaten var.';
    }
    return null;
  }

  Future<void> _createDepartment() async {
    setState(() => _nameErrorText = null);
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameErrorText = 'Birim adı girin');
      return;
    }

    setState(() => _isCreating = true);
    try {
      await _client.from('departments').insert({'name': name});
      _nameController.clear();
      await _loadDepartments();
    } catch (e) {
      if (!mounted) return;
      final inlineMessage = _describeSaveError(e);
      if (inlineMessage != null) {
        setState(() => _nameErrorText = inlineMessage);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Birim eklenemedi. Lütfen tekrar deneyin.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> department) async {
    try {
      await _client
          .from('departments')
          .update({'is_active': !(department['is_active'] as bool)})
          .eq('id', department['id']);
      await _loadDepartments();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Güncellenemedi. Lütfen tekrar deneyin.')),
      );
    }
  }

  Future<void> _showEditDialog(Map<String, dynamic> department) async {
    final controller = TextEditingController(text: department['name'] as String);
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Birim Adını Düzenle'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(labelText: 'Birim Adı', errorText: errorText),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('İptal'),
            ),
            TextButton(
              onPressed: () async {
                final newName = controller.text.trim();
                if (newName.isEmpty) {
                  setDialogState(() => errorText = 'Birim adı girin');
                  return;
                }
                try {
                  await _client
                      .from('departments')
                      .update({'name': newName})
                      .eq('id', department['id']);
                  if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                  await _loadDepartments();
                } catch (e) {
                  final inlineMessage = _describeSaveError(e);
                  setDialogState(
                    () => errorText = inlineMessage ?? 'Güncellenemedi. Lütfen tekrar deneyin.',
                  );
                }
              },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Birim Yönetimi')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: 'Yeni Birim Adı',
                      errorText: _nameErrorText,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _isCreating ? null : _createDepartment,
                  child: _isCreating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Ekle'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            const Text('Birimler', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
              child: _isLoadingDepartments
                  ? const Center(child: CircularProgressIndicator())
                  : _departments.isEmpty
                      ? const Center(child: Text('Henüz birim eklenmedi.'))
                      : ListView.builder(
                          itemCount: _departments.length,
                          itemBuilder: (context, index) {
                            final department = _departments[index];
                            final isActive = department['is_active'] as bool;
                            return ListTile(
                              key: ValueKey(department['id']),
                              title: Text(department['name'] as String),
                              subtitle: Text(
                                isActive ? 'Aktif' : 'Pasif',
                                style: TextStyle(
                                  color: isActive ? Colors.green : Colors.grey,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit),
                                    tooltip: 'Adını Düzenle',
                                    onPressed: () => _showEditDialog(department),
                                  ),
                                  TextButton(
                                    onPressed: () => _toggleActive(department),
                                    child: Text(isActive ? 'Pasif Yap' : 'Aktif Yap'),
                                  ),
                                ],
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

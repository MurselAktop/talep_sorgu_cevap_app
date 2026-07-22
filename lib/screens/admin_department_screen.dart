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
      // Bu await sırasında kullanıcı geri tuşuyla ekrandan çıkmış olabilir
      // (State dispose edilmiş olabilir) — mounted kontrolü olmadan setState
      // çağırmak framework'te assertion hatasına yol açar.
      if (!mounted) return;
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
      // Bu await sırasında ekran dispose edilmişse _nameController da
      // dispose edilmiş olur — dispose edilmiş bir controller'a .clear()
      // çağırmak hataya yol açar.
      if (!mounted) return;
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

  void _showEditDialog(Map<String, dynamic> department) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => _EditDepartmentDialog(
        initialName: department['name'] as String,
        onSubmit: (dialogContext, newName) =>
            _updateDepartmentName(dialogContext, department, newName),
      ),
    );
  }

  /// GERÇEK KÖK NEDEN (gerçek cihazda `flutter attach` ile tam stack trace
  /// yakalanarak doğrulandı — `_dependents.isEmpty` sadece bir yan etkiydi,
  /// asıl hata "A TextEditingController was used after being disposed"):
  /// `_showEditDialog` eskiden `TextEditingController`'ı yerel bir
  /// değişkende tutup `await showDialog(...)` döndükten HEMEN sonra elle
  /// `dispose()` ediyordu. `showDialog()`'un döndürdüğü Future,
  /// `Navigator.pop()` çağrıldığı ANDA tamamlanır — ama `pop()` dialogu
  /// ağaçtan ANINDA kaldırmaz, kapanış (exit) animasyonu süresince (birkaç
  /// frame boyunca) dialogun widget'ları hâlâ rebuild olmaya devam eder. Bu
  /// yüzden controller, animasyon daha bitmeden, `TextField` ona hâlâ
  /// `addListener` çağırmaya çalışırken dispose ediliyordu — zamanlamaya
  /// bağlı olduğu için bazen sıyırıp geçiyor, bazen çöküyordu.
  ///
  /// Kalıcı çözüm: `request_detail_screen.dart`'taki `_ResolveReportDialog`/
  /// `_EditRequestDialog` ile AYNI, bu kod tabanında zaten kanıtlanmış
  /// deseni izlemek — dialogu kendi `TextEditingController`'ını
  /// `initState`'te oluşturup kendi `State.dispose()`'unda temizleyen
  /// gerçek bir `StatefulWidget` yapmak. Böylece controller'ın ömrü,
  /// `showDialog`'un Future'ının ne zaman tamamlandığına değil, o
  /// `StatefulWidget`'ın Element'inin gerçekten ne zaman unmount olduğuna
  /// (yani kapanış animasyonu tamamen bitene kadar) bağlı olur.
  Future<String?> _updateDepartmentName(
    BuildContext dialogContext,
    Map<String, dynamic> department,
    String newName,
  ) async {
    try {
      await _client.from('departments').update({'name': newName}).eq('id', department['id']);
      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
      if (mounted) setState(() => department['name'] = newName);
      return null;
    } catch (e) {
      return _describeSaveError(e) ?? 'Güncellenemedi. Lütfen tekrar deneyin.';
    }
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

/// "Adını Düzenle" ile açılan, birim adını alan dialog. `request_detail_screen.dart`
/// içindeki `_ResolveReportDialog`/`_EditRequestDialog` ile aynı deseni izler:
/// kendi `TextEditingController`'ını kendi `State.dispose()`'unda temizler
/// (bkz. `_updateDepartmentName` üzerindeki kök neden açıklaması) —
/// `onSubmit`, başarıda `null`, hatada gösterilecek Türkçe mesajı döndürür.
class _EditDepartmentDialog extends StatefulWidget {
  final String initialName;
  final Future<String?> Function(BuildContext dialogContext, String newName) onSubmit;

  const _EditDepartmentDialog({required this.initialName, required this.onSubmit});

  @override
  State<_EditDepartmentDialog> createState() => _EditDepartmentDialogState();
}

class _EditDepartmentDialogState extends State<_EditDepartmentDialog> {
  late final _nameController = TextEditingController(text: widget.initialName);
  bool _isSubmitting = false;
  String? _errorText;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty) {
      setState(() => _errorText = 'Birim adı girin');
      return;
    }
    setState(() {
      _errorText = null;
      _isSubmitting = true;
    });
    final error = await widget.onSubmit(context, newName);
    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _errorText = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Birim Adını Düzenle'),
      content: TextField(
        controller: _nameController,
        autofocus: true,
        decoration: InputDecoration(labelText: 'Birim Adı', errorText: _errorText),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('İptal'),
        ),
        TextButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Kaydet'),
        ),
      ],
    );
  }
}

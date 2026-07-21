import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/turkiye_iller.dart';
import '../services/supabase_service.dart';
import '../utils/phone_input_formatter.dart';
import '../utils/validators.dart';
import 'change_password_screen.dart';

const Map<String, String> _profileRoleLabels = {
  'vatandas': 'Vatandaş',
  'personel': 'Personel',
  'mudur': 'Müdür',
  'admin': 'Admin',
};

/// Kullanıcının kendi hesap bilgilerini görüp düzenlediği ekran (Faz 2).
/// full_name/phone/il/ilce düzenlenebilir; email/role/department salt
/// okunurdur — role/department_id zaten RLS'in `kendi_profilini_güncelleyebilir`
/// politikasında `WITH CHECK` ile korunuyor, bu yüzden UPDATE payload'ına
/// hiç dahil edilmiyor. tc_no bu ekranda hiç gösterilmiyor (Faz 1 kararı:
/// sadece kullanıcının kendisi + admin, ayrı bir users_private tablosunda).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const _networkTimeout = Duration(seconds: 15);

  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _ilceController = TextEditingController();
  String? _selectedIl;

  bool _isLoadingProfile = true;
  bool _isSaving = false;
  String? _loadError;
  String _email = '';
  String _roleLabel = '';
  String _departmentLabel = 'Yok';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _ilceController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId == null) {
      setState(() {
        _isLoadingProfile = false;
        _loadError = 'Oturum bulunamadı.';
      });
      return;
    }

    try {
      final profile = await SupabaseService.client
          .from('users')
          .select('full_name, email, phone, il, ilce, role, department_id')
          .eq('id', userId)
          .single()
          .timeout(_networkTimeout);

      String departmentLabel = 'Yok';
      final departmentId = profile['department_id'] as String?;
      if (departmentId != null) {
        final department = await SupabaseService.client
            .from('departments')
            .select('name')
            .eq('id', departmentId)
            .single()
            .timeout(_networkTimeout);
        departmentLabel = department['name'] as String? ?? 'Yok';
      }

      final rawPhone = profile['phone'] as String?;
      if (!mounted) return;
      setState(() {
        _fullNameController.text = profile['full_name'] as String? ?? '';
        _phoneController.text = (rawPhone == null || rawPhone.isEmpty)
            ? ''
            : Validators.phoneToDisplay(rawPhone);
        _selectedIl = profile['il'] as String?;
        _ilceController.text = profile['ilce'] as String? ?? '';
        _email = profile['email'] as String? ?? '';
        final role = profile['role'] as String? ?? '';
        _roleLabel = _profileRoleLabels[role] ?? role;
        _departmentLabel = departmentLabel;
        _isLoadingProfile = false;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _isLoadingProfile = false;
        _loadError =
            'Bağlantı zaman aşımına uğradı. Lütfen tekrar deneyin.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingProfile = false;
        _loadError = 'Profil bilgileri yüklenemedi. Lütfen tekrar deneyin.';
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId == null) return;

    setState(() => _isSaving = true);
    try {
      // role/department_id BİLİNÇLİ olarak payload'a dahil edilmiyor —
      // RLS zaten self-update ile değişmelerini engelliyor, ama gereksiz
      // bir reddedilmeyi önlemek için burada hiç gönderilmiyorlar.
      await SupabaseService.client
          .from('users')
          .update({
            'full_name': _fullNameController.text.trim(),
            'phone': Validators.normalizePhone(_phoneController.text),
            'il': _selectedIl,
            'ilce': _ilceController.text.trim(),
          })
          .eq('id', userId)
          .timeout(_networkTimeout);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil bilgileriniz güncellendi.')),
      );
    } on TimeoutException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bağlantı zaman aşımına uğradı. Lütfen tekrar deneyin.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Güncelleme başarısız oldu. Lütfen tekrar deneyin.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profilim')),
      body: _isLoadingProfile
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? Center(child: Text(_loadError!))
          : Center(
              child: SingleChildScrollView(
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
                            initialValue: _email,
                            enabled: false,
                            decoration: const InputDecoration(
                              labelText: 'E-posta',
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            initialValue: _roleLabel,
                            enabled: false,
                            decoration: const InputDecoration(
                              labelText: 'Rol',
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            initialValue: _departmentLabel,
                            enabled: false,
                            decoration: const InputDecoration(
                              labelText: 'Birim',
                            ),
                          ),
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: _fullNameController,
                            decoration: const InputDecoration(
                              labelText: 'Ad Soyad',
                            ),
                            validator: (value) =>
                                (value == null || value.trim().isEmpty)
                                ? 'Ad soyad girin'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            inputFormatters: [PhoneInputFormatter()],
                            decoration: const InputDecoration(
                              labelText: 'Telefon',
                              hintText: '+90 (5XX) XXX XX XX',
                            ),
                            validator: Validators.phone,
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            initialValue: _selectedIl,
                            decoration: const InputDecoration(
                              labelText: 'İl',
                            ),
                            items: [
                              for (final il in turkiyeIlleri)
                                DropdownMenuItem(value: il, child: Text(il)),
                            ],
                            onChanged: (value) =>
                                setState(() => _selectedIl = value),
                            validator: (value) =>
                                value == null ? 'İl seçin' : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _ilceController,
                            decoration: const InputDecoration(
                              labelText: 'İlçe',
                            ),
                            validator: (value) =>
                                Validators.requiredField(value, 'İlçe girin'),
                          ),
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: _isSaving ? null : _save,
                            child: _isSaving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Kaydet'),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: _isSaving
                                ? null
                                : () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const ChangePasswordScreen(),
                                    ),
                                  ),
                            child: const Text('Şifre Değiştir'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

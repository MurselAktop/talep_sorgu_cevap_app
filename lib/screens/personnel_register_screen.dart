import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';

/// Personel/müdür/admin kaydı ekranı. Vatandaş kaydından (register_screen.dart)
/// tamamen ayrı, bağımsız bir ekrandır — kendi kendine kayıt yerine, admin'in
/// önceden ürettiği bir davet koduyla çalışır. AuthService.signUp() çağrılırken
/// full_name ile birlikte invite_code metadata olarak gönderilir; veritabanındaki
/// handle_new_user() trigger'ı kodu personnel_invites tablosunda doğrulayıp
/// kodun tanımladığı rol/birimle profil oluşturur, kodu "kullanıldı" işaretler.
class PersonnelRegisterScreen extends StatefulWidget {
  const PersonnelRegisterScreen({super.key});

  @override
  State<PersonnelRegisterScreen> createState() => _PersonnelRegisterScreenState();
}

class _PersonnelRegisterScreenState extends State<PersonnelRegisterScreen> {
  static final _emailRegex = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');

  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _inviteCodeController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _inviteCodeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await AuthService.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        fullName: _fullNameController.text.trim(),
        inviteCode: _inviteCodeController.text.trim().toUpperCase(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kaydınız başarıyla oluşturuldu.')),
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_describeAuthError(e))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bir hata oluştu, lütfen tekrar deneyin.')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Davet kodu hatası, handle_new_user() trigger'ının Postgres exception'ı
  // GoTrue tarafından sarmalanarak AuthException.message içine düşüyor; bu
  // yüzden hem tam mesaja hem de "davet" geçen genel bir eşleşmeye bakıyoruz.
  String _describeAuthError(AuthException e) {
    final message = e.message;
    if (message == 'Geçersiz veya kullanılmış davet kodu.' ||
        message.toLowerCase().contains('davet')) {
      return 'Girdiğiniz davet kodu geçersiz veya daha önce kullanılmış. Lütfen kodu kontrol edip tekrar deneyin.';
    }

    final lower = message.toLowerCase();
    if (lower.contains('already registered')) {
      return 'Bu e-posta adresi zaten kayıtlı.';
    }
    if (lower.contains('password') && lower.contains('least')) {
      return 'Şifre en az 6 karakter olmalıdır.';
    }
    if (lower.contains('invalid') && lower.contains('email')) {
      return 'Geçersiz e-posta adresi.';
    }
    return 'Kayıt işlemi başarısız oldu. Lütfen bilgilerinizi kontrol edin.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Personel Kaydı')),
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
                    controller: _fullNameController,
                    decoration: const InputDecoration(labelText: 'Ad Soyad'),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty) ? 'Ad soyad girin' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'E-posta'),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return 'E-posta girin';
                      if (!_emailRegex.hasMatch(value.trim())) {
                        return 'Geçerli bir e-posta adresi girin';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Şifre'),
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'Şifre girin';
                      if (value.length < 6) return 'Şifre en az 6 karakter olmalı';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _inviteCodeController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Davet Kodu'),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty) ? 'Davet kodu girin' : null,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _isLoading ? null : _submit,
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Kayıt Ol'),
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

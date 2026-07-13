import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../services/supabase_service.dart';
import 'login_screen.dart';

/// Vatandaş kaydı ekranı. AuthService.signUp() çağrılırken full_name
/// metadata olarak gönderilir; veritabanındaki handle_new_user() trigger'ı
/// bunu okuyup public.users'a otomatik profil açar.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
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
      );

      // Yerel geliştirmede GOTRUE_MAILER_AUTOCONFIRM=true olduğu için signUp
      // kullanıcıyı otomatik olarak oturum açmış hale getiriyor. Kayıt
      // sonrası doğrudan ana ekrana atlamak yerine kullanıcıyı bilinçli
      // olarak giriş ekranına yönlendirmek istiyoruz, bu yüzden oturumu
      // burada kapatıyoruz.
      await SupabaseService.client.auth.signOut();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kaydınız oluşturuldu. Şimdi giriş yapabilirsiniz.')),
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_describeAuthError(e))),
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

  // Supabase (GoTrue) hatalarını kısa Türkçe mesajlara çeviriyoruz.
  String _describeAuthError(AuthException e) {
    final message = e.message.toLowerCase();
    if (message.contains('already registered')) {
      return 'Bu e-posta adresi zaten kayıtlı.';
    }
    if (message.contains('password') && message.contains('least')) {
      return 'Şifre en az 6 karakter olmalıdır.';
    }
    if (message.contains('invalid') && message.contains('email')) {
      return 'Geçersiz e-posta adresi.';
    }
    return 'Kayıt işlemi başarısız oldu. Lütfen bilgilerinizi kontrol edin.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kayıt Ol')),
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
                    validator: (value) =>
                        (value == null || value.trim().isEmpty) ? 'E-posta girin' : null,
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
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _isLoading
                        ? null
                        : () => Navigator.of(context).pushReplacement(
                              MaterialPageRoute(builder: (_) => const LoginScreen()),
                            ),
                    child: const Text('Zaten hesabın var mı? Giriş yap'),
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

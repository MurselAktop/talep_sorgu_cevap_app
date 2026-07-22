import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/turkiye_iller.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';
import '../utils/phone_input_formatter.dart';
import '../utils/validators.dart';
import 'login_screen.dart';

/// Vatandaş kaydı ekranı. AuthService.signUp() çağrılırken full_name ve
/// Faz 1 alanları (tc_no, phone, il, ilce) metadata olarak gönderilir;
/// veritabanındaki handle_new_user() trigger'ı bunları okuyup public.users'a
/// (tc_no'yu ise kısıtlı erişimli public.users_private'a) yazar.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // Ağ isteği hiç cevap vermezse (örn. yanlış/erişilemez Supabase URL'i)
  // butonun sonsuza kadar dönmemesi için: await burada asla kendiliğinden
  // tamamlanmayabilir, .timeout() bu durumda bir TimeoutException fırlatır.
  static const _networkTimeout = Duration(seconds: 15);

  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _tcNoController = TextEditingController();
  final _phoneController = TextEditingController();
  final _ilceController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _selectedIl;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _emailErrorText;
  String? _tcNoErrorText;

  @override
  void dispose() {
    _fullNameController.dispose();
    _tcNoController.dispose();
    _phoneController.dispose();
    _ilceController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _emailErrorText = null;
      _tcNoErrorText = null;
    });
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      // Bkz. AuthService.checkRegistrationAvailability dokümantasyonu:
      // handle_new_user() trigger'ının hata mesajı GoTrue tarafından
      // sansürlendiği için, tc_no doğrulaması signUp()'tan ÖNCE, ayrı bir
      // RPC ile yapılıyor — buradan dönen hata mesajı güvenilir.
      await AuthService.checkRegistrationAvailability(
        tcNo: _tcNoController.text.trim(),
      ).timeout(_networkTimeout);

      await AuthService.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        fullName: _fullNameController.text.trim(),
        tcNo: _tcNoController.text.trim(),
        phone: Validators.normalizePhone(_phoneController.text),
        il: _selectedIl!,
        ilce: _ilceController.text.trim(),
      ).timeout(_networkTimeout);

      // Yerel geliştirmede GOTRUE_MAILER_AUTOCONFIRM=true olduğu için signUp
      // kullanıcıyı otomatik olarak oturum açmış hale getiriyor. Kayıt
      // sonrası doğrudan ana ekrana atlamak yerine kullanıcıyı bilinçli
      // olarak giriş ekranına yönlendirmek istiyoruz, bu yüzden oturumu
      // burada kapatıyoruz.
      await SupabaseService.client.auth.signOut().timeout(_networkTimeout);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kaydınız oluşturuldu. Şimdi giriş yapabilirsiniz.'),
        ),
      );
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
    } on PostgrestException catch (e) {
      // check_registration_availability'nin fırlattığı hata — bu ekranda
      // sadece tc_no kontrolü olduğu için mesaj doğrudan o alana yazılabilir.
      if (!mounted) return;
      setState(() => _tcNoErrorText = e.message);
    } on AuthException catch (e) {
      if (!mounted) return;
      if (e.message.toLowerCase().contains('already registered')) {
        setState(
          () => _emailErrorText =
              'Bu e-posta adresi sistemde zaten kayıtlı. Lütfen giriş yapın.',
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_describeAuthError(e))));
      }
    } on TimeoutException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bağlantı zaman aşımına uğradı. Lütfen internet bağlantınızı kontrol edip tekrar deneyin.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Supabase (GoTrue) hatalarını kısa Türkçe mesajlara çeviriyoruz. "E-posta
  // zaten kayıtlı" ve "tc_no zaten kayıtlı" hataları burada değil, inline
  // alan hataları olarak _submit içinde ayrıca ele alınıyor.
  String _describeAuthError(AuthException e) {
    final message = e.message.toLowerCase();
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
        // Form Faz 1 alanlarıyla uzadığı için küçük ekranlarda klavye
        // açıkken taşmasın diye kaydırılabilir yapıldı.
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
                      controller: _fullNameController,
                      decoration: const InputDecoration(labelText: 'Ad Soyad'),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                          ? 'Ad soyad girin'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _tcNoController,
                      keyboardType: TextInputType.number,
                      maxLength: 11,
                      decoration: InputDecoration(
                        labelText: 'T.C. Kimlik No',
                        counterText: '',
                        errorText: _tcNoErrorText,
                      ),
                      validator: Validators.tcNo,
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
                      decoration: const InputDecoration(labelText: 'İl'),
                      items: [
                        for (final il in turkiyeIlleri)
                          DropdownMenuItem(value: il, child: Text(il)),
                      ],
                      onChanged: (value) => setState(() => _selectedIl = value),
                      validator: (value) => value == null ? 'İl seçin' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _ilceController,
                      decoration: const InputDecoration(labelText: 'İlçe'),
                      validator: (value) =>
                          Validators.requiredField(value, 'İlçe girin'),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: 'E-posta',
                        errorText: _emailErrorText,
                      ),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                          ? 'E-posta girin'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Şifre',
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty)
                          return 'Şifre girin';
                        if (value.length < 6)
                          return 'Şifre en az 6 karakter olmalı';
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
                              MaterialPageRoute(
                                builder: (_) => const LoginScreen(),
                              ),
                            ),
                      child: const Text('Zaten hesabın var mı? Giriş yap'),
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

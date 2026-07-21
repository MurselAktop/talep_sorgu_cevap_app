import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../services/supabase_service.dart';
import 'home_screen.dart';

/// Şifremi unuttum akışının tamamlandığı ekran (Faz 2). E-postadaki
/// sıfırlama LİNKİ bu projede işlevsiz bırakıldı (bkz. forgot_password_screen.dart
/// dokümantasyonu — link, uygulamanın hiç açılmadığı `localhost:3000`'e
/// yönlendiriyor, deep link altyapısı kurulmadı). Bunun yerine aynı
/// e-postadaki 6 haneli alternatif kod kullanılıyor: `auth.verifyOTP` ile
/// doğrulanıp bir kurtarma oturumu (session) elde ediliyor, ardından
/// `AuthService.updatePassword` ile yeni şifre kaydediliyor. Bu ikisi aynı
/// tek kullanımlık token'ın iki temsili — biri kullanılınca diğeri de
/// geçersiz olur (curl ile doğrulandı).
class ResetPasswordScreen extends StatefulWidget {
  final String email;

  const ResetPasswordScreen({super.key, required this.email});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  static const _networkTimeout = Duration(seconds: 15);

  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isSubmitting = false;
  String? _codeErrorText;

  @override
  void dispose() {
    _codeController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _codeErrorText = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      // Başarılı olursa supabase_flutter, dönen oturumu otomatik olarak
      // geçerli oturum yapar — bu yüzden updatePassword() için ayrıca
      // giriş yapmaya gerek yok.
      await SupabaseService.client.auth
          .verifyOTP(
            type: OtpType.recovery,
            email: widget.email,
            token: _codeController.text.trim(),
          )
          .timeout(_networkTimeout);

      await AuthService.updatePassword(
        _newPasswordController.text,
      ).timeout(_networkTimeout);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Şifreniz değiştirildi, giriş yapıldı.')),
      );
      // verifyOTP ile zaten geçerli bir oturum elde edildiği için kullanıcı
      // tekrar giriş yapmak zorunda bırakılmıyor, doğrudan ana ekrana geçiyor.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomePage()),
        (route) => false,
      );
    } on AuthException catch (_) {
      if (!mounted) return;
      setState(
        () => _codeErrorText =
            'Kod hatalı veya süresi dolmuş. E-postanızdaki en güncel kodu kontrol edin.',
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
          content: Text('Şifre sıfırlanamadı. Lütfen tekrar deneyin.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kod ile Şifre Sıfırla')),
      body: Center(
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
                    Text(
                      '${widget.email} adresine gönderilen e-postadaki '
                      '6 haneli kodu girin.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _codeController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: InputDecoration(
                        labelText: 'Doğrulama Kodu',
                        counterText: '',
                        errorText: _codeErrorText,
                      ),
                      validator: (value) =>
                          (value == null || value.trim().length != 6)
                          ? '6 haneli kodu girin'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _newPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Yeni Şifre',
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Yeni şifrenizi girin';
                        }
                        if (value.length < 6) {
                          return 'Şifre en az 6 karakter olmalı';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Yeni Şifre (Tekrar)',
                      ),
                      validator: (value) =>
                          value != _newPasswordController.text
                          ? 'Şifreler eşleşmiyor'
                          : null,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _isSubmitting ? null : _submit,
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Text('Şifreyi Sıfırla'),
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

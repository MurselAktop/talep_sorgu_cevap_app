import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'reset_password_screen.dart';

/// Şifremi unuttum ekranı (Faz 2). Kullanıcı e-postasını girer, Supabase'in
/// yerleşik `resetPasswordForEmail` çağrısıyla bir sıfırlama e-postası
/// gönderilir. Bu e-posta hem bir link hem de 6 haneli bir kod içerir; link
/// bu projede bilinçli olarak KULLANILMIYOR (uygulamanın hiç açılmadığı
/// `localhost:3000`'e yönlendiriyor, deep link altyapısı kurulmadı — bkz.
/// CLAUDE.md Faz 2 notları). Bunun yerine kullanıcı 6 haneli kodu
/// `ResetPasswordScreen`'e girer; o ekran `auth.verifyOTP` ile kodu
/// doğrulayıp yeni şifreyi kaydeder.
///
/// Yerel geliştirmede gönderilen e-postayı görmek için Inbucket
/// (http://localhost:9000) kullanılır.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  static const _networkTimeout = Duration(seconds: 15);

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isSending = false;
  bool _sent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSending = true);
    try {
      await AuthService.resetPasswordForEmail(
        _emailController.text.trim(),
      ).timeout(_networkTimeout);
    } on TimeoutException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bağlantı zaman aşımına uğradı. Lütfen tekrar deneyin.',
          ),
        ),
      );
      setState(() => _isSending = false);
      return;
    } catch (_) {
      // Hesabın var olup olmadığını sızdırmamak için hata durumunda da
      // aynı "gönderildi" mesajı gösterilir — register/login ekranlarındaki
      // e-posta sızıntısı önleme prensibiyle tutarlı.
    }

    if (!mounted) return;
    setState(() {
      _isSending = false;
      _sent = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Şifremi Unuttum')),
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _sent
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Bu e-posta adresine kayıtlı bir hesap varsa, bir '
                          'e-posta gönderildi. E-postadaki LİNKE DEĞİL, '
                          'içindeki 6 haneli koda bakın ve aşağıdaki butonla '
                          'devam edin.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ResetPasswordScreen(
                                email: _emailController.text.trim(),
                              ),
                            ),
                          ),
                          child: const Text('Kodu Girdim, Devam Et'),
                        ),
                      ],
                    )
                  : Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Hesabınıza kayıtlı e-posta adresini girin, size '
                            'bir 6 haneli doğrulama kodu gönderelim.',
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'E-posta',
                            ),
                            validator: (value) =>
                                (value == null || value.trim().isEmpty)
                                ? 'E-posta girin'
                                : null,
                          ),
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: _isSending ? null : _submit,
                            child: _isSending
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Doğrulama Kodu Gönder'),
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

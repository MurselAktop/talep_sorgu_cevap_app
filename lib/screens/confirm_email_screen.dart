import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import 'home_screen.dart';

/// Kayıt sonrası e-posta doğrulama ekranı (2026-07-22). `reset_password_screen.dart`
/// ile AYNI deseni izler: e-postadaki LİNK bilinçli olarak kullanılmıyor
/// (uygulamanın hiç açılmadığı `SITE_URL`'e yönlendiriyor), bunun yerine aynı
/// e-postadaki 6 haneli kod `auth.verifyOTP(type: OtpType.signup, ...)` ile
/// doğrulanıyor. Başarılı doğrulama zaten geçerli bir oturum bıraktığı için
/// kullanıcı tekrar giriş yapmaya zorlanmadan doğrudan ana ekrana yönlendirilir.
class ConfirmEmailScreen extends StatefulWidget {
  final String email;

  const ConfirmEmailScreen({super.key, required this.email});

  @override
  State<ConfirmEmailScreen> createState() => _ConfirmEmailScreenState();
}

class _ConfirmEmailScreenState extends State<ConfirmEmailScreen> {
  static const _networkTimeout = Duration(seconds: 15);

  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  bool _isSubmitting = false;
  bool _isResending = false;
  String? _codeErrorText;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _codeErrorText = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      await AuthService.verifySignupOtp(
        email: widget.email,
        token: _codeController.text.trim(),
      ).timeout(_networkTimeout);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('E-postanız doğrulandı, giriş yapıldı.')),
      );
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
          content: Text('Bağlantı zaman aşımına uğradı. Lütfen tekrar deneyin.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Doğrulama yapılamadı. Lütfen tekrar deneyin.')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _isResending = true);
    try {
      await AuthService.resendSignupConfirmation(
        widget.email,
      ).timeout(_networkTimeout);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Yeni bir doğrulama kodu gönderildi.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kod gönderilemedi. Lütfen tekrar deneyin.')),
      );
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('E-posta Doğrulama')),
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
                    const Icon(Icons.mark_email_read_outlined, size: 56),
                    const SizedBox(height: 16),
                    Text(
                      '${widget.email} adresine bir doğrulama e-postası '
                      'gönderildi. E-postadaki LİNKE DEĞİL, içindeki 6 haneli '
                      'koda bakın ve aşağıya girin.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
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
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _isSubmitting ? null : _submit,
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Doğrula ve Devam Et'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _isResending ? null : _resend,
                      child: _isResending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Kodu Tekrar Gönder'),
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

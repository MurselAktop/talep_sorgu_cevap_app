import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../services/local_prefs_service.dart';
import '../services/supabase_service.dart';
import 'home_screen.dart';
import 'login_screen.dart';

/// Giriş anındaki ikinci doğrulama adımı (2026-07-27, 2026-07-27 akış düzeltmesi).
///
/// `login_screen.dart`, şifre + rol kontrolü geçtikten sonra — "Beni Hatırla"
/// İŞARETLİ DEĞİLSE — bu ekrana yönlendirir. Şifre oturumu hâlâ açıktır;
/// kod doğrulanana kadar ana ekrana geçilmez. Kullanıcı geri dönerse oturum
/// kapatılır.
///
/// Eski hata: login ekranında `signOut()` + `sendLoginOtp()` peş peşe
/// çağrılıyordu; OTP e-postası (rate limit vb.) başarısız olunca bu
/// `AuthException` şifre hatası gibi gösterilip doğrulama ekranı hiç
/// açılmıyordu. Artık kod gönderimi BU ekranda yapılıyor.
class LoginOtpScreen extends StatefulWidget {
  final String email;

  /// `true` ise ekran açılır açılmaz doğrulama kodu gönderilir (normal akış).
  final bool sendOtpOnOpen;

  const LoginOtpScreen({
    super.key,
    required this.email,
    this.sendOtpOnOpen = true,
  });

  @override
  State<LoginOtpScreen> createState() => _LoginOtpScreenState();
}

class _LoginOtpScreenState extends State<LoginOtpScreen> {
  static const _networkTimeout = Duration(seconds: 15);

  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  bool _isSubmitting = false;
  bool _isResending = false;
  bool _isSendingInitial = false;
  String? _codeErrorText;
  String? _sendStatusMessage;

  @override
  void initState() {
    super.initState();
    if (widget.sendOtpOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _sendInitialOtp());
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _sendInitialOtp() async {
    setState(() {
      _isSendingInitial = true;
      _sendStatusMessage = null;
    });
    try {
      await AuthService.sendLoginOtp(widget.email).timeout(_networkTimeout);
      if (!mounted) return;
      setState(() {
        _sendStatusMessage =
            'Doğrulama kodu e-posta adresinize gönderildi. LİNKE değil, 6 haneli koda bakın.';
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _sendStatusMessage = _describeSendError(e));
    } on TimeoutException {
      if (!mounted) return;
      setState(
        () => _sendStatusMessage =
            'Kod gönderimi zaman aşımına uğradı. "Kodu Tekrar Gönder" ile deneyin.',
      );
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _sendStatusMessage =
            'Kod gönderilemedi. "Kodu Tekrar Gönder" ile tekrar deneyin.',
      );
    } finally {
      if (mounted) setState(() => _isSendingInitial = false);
    }
  }

  String _describeSendError(AuthException e) {
    final message = e.message.toLowerCase();
    if (message.contains('rate limit') ||
        message.contains('over_email_send_rate_limit') ||
        message.contains('for security purposes')) {
      return 'Çok sık kod istendi. Birkaç dakika bekleyip "Kodu Tekrar Gönder"e basın.';
    }
    return 'Kod gönderilemedi: ${e.message}';
  }

  Future<void> _abortAndReturnToLogin() async {
    try {
      await SupabaseService.client.auth.signOut();
    } catch (_) {
      // Sessizce yutulur.
    }
    await LocalPrefsService.setRememberMe(false);
    await LocalPrefsService.setActiveSessionToken(null);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _submit() async {
    setState(() => _codeErrorText = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      await AuthService.verifyLoginOtp(
        email: widget.email,
        token: _codeController.text.trim(),
      ).timeout(_networkTimeout);

      await AuthService.registerAndCacheActiveSession();

      if (!mounted) return;
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
      await AuthService.sendLoginOtp(widget.email).timeout(_networkTimeout);
      if (!mounted) return;
      setState(() {
        _sendStatusMessage = 'Yeni bir doğrulama kodu gönderildi.';
        _codeErrorText = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Yeni bir doğrulama kodu gönderildi.')),
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _sendStatusMessage = _describeSendError(e));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_describeSendError(e))),
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _abortAndReturnToLogin();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Giriş Doğrulama'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _abortAndReturnToLogin,
          ),
        ),
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
                      Icon(
                        Icons.verified_user_outlined,
                        size: 56,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Güvenliğiniz için, "${widget.email}" adresine bir '
                        'doğrulama kodu gönderiliyor. E-postadaki LİNKE DEĞİL, '
                        'içindeki 6 haneli koda bakın ve aşağıya girin.',
                        textAlign: TextAlign.center,
                      ),
                      if (_isSendingInitial) ...[
                        const SizedBox(height: 16),
                        const CircularProgressIndicator(),
                      ],
                      if (_sendStatusMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _sendStatusMessage!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _codeController,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        autofocus: true,
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
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                        onPressed: _isSubmitting ? null : _submit,
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Doğrula ve Giriş Yap'),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: (_isResending || _isSendingInitial) ? null : _resend,
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
      ),
    );
  }
}

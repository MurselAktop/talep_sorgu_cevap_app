import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../services/supabase_service.dart';

/// Giriş yapmış kullanıcının şifresini değiştirdiği ekran (Faz 2).
///
/// Önce mevcut şifre `signInWithPassword` ile yeniden doğrulanır — oturumu
/// ele geçiren birinin eski şifreyi bilmeden şifre değiştirememesi için.
/// Doğrulama başarılıysa `AuthService.updatePassword` çağrılır.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  static const _networkTimeout = Duration(seconds: 15);

  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isSaving = false;
  String? _currentPasswordErrorText;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _currentPasswordErrorText = null);
    if (!_formKey.currentState!.validate()) return;

    final email = SupabaseService.client.auth.currentUser?.email;
    if (email == null) return;

    setState(() => _isSaving = true);
    try {
      await AuthService.signInWithPassword(
        email: email,
        password: _currentPasswordController.text,
      ).timeout(_networkTimeout);

      await AuthService.updatePassword(
        _newPasswordController.text,
      ).timeout(_networkTimeout);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Şifreniz değiştirildi.')),
      );
      Navigator.of(context).pop();
    } on AuthException catch (_) {
      if (!mounted) return;
      setState(() => _currentPasswordErrorText = 'Mevcut şifreniz yanlış.');
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
          content: Text('Şifre değiştirilemedi. Lütfen tekrar deneyin.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Şifre Değiştir')),
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
                    TextFormField(
                      controller: _currentPasswordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Mevcut Şifre',
                        errorText: _currentPasswordErrorText,
                      ),
                      validator: (value) => (value == null || value.isEmpty)
                          ? 'Mevcut şifrenizi girin'
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
                      onPressed: _isSaving ? null : _submit,
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Text('Şifreyi Değiştir'),
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

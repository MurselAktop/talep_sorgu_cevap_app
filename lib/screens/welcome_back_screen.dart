import 'dart:async';

import 'package:flutter/material.dart';

import '../services/local_prefs_service.dart';
import '../services/supabase_service.dart';
import 'home_screen.dart';
import 'login_screen.dart';

/// "Beni Hatırla" işaretlenmiş ve uygulama açılışında hâlâ (yerelde) bir
/// Supabase oturumu bulunduğunda AuthGate tarafından normal giriş formu
/// yerine gösterilir. Şifre tekrar sorulmaz.
///
/// "Giriş Yap" butonu, AuthGate'in sadece yerelde baktığı oturumun sunucu
/// tarafında hâlâ geçerli olduğunu (ve hesabın pasifleştirilmemiş olduğunu)
/// sessizce doğrular — `users` tablosuna atılan sorgu, geçersiz/süresi
/// dolmuş bir oturumda zaten reddedilir, bu yüzden ayrı bir "token geçerli
/// mi" kontrolüne gerek yok. Doğrulama başarısızsa otomatik olarak normal
/// (boş) giriş formuna düşülür.
class WelcomeBackScreen extends StatefulWidget {
  const WelcomeBackScreen({super.key, required this.cachedFullName});

  final String? cachedFullName;

  @override
  State<WelcomeBackScreen> createState() => _WelcomeBackScreenState();
}

class _WelcomeBackScreenState extends State<WelcomeBackScreen> {
  static const _networkTimeout = Duration(seconds: 15);

  bool _isLoading = false;

  Future<void> _fallbackToLoginForm() async {
    await SupabaseService.client.auth.signOut();
    await LocalPrefsService.setRememberMe(false);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  Future<void> _continue() async {
    setState(() => _isLoading = true);
    try {
      final userId = SupabaseService.client.auth.currentUser?.id;
      if (userId == null) {
        await _fallbackToLoginForm();
        return;
      }

      final profile = await SupabaseService.client
          .from('users')
          .select('is_active')
          .eq('id', userId)
          .single()
          .timeout(_networkTimeout);

      if (profile['is_active'] == false) {
        await SupabaseService.client.auth.signOut();
        await LocalPrefsService.setRememberMe(false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hesabınız pasifleştirilmiş. Lütfen yönetici ile iletişime geçin.'),
          ),
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
        return;
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomePage()),
      );
    } on TimeoutException {
      // Sadece bir ağ aksaklığı olabilir; oturumu geçersiz saymadan bu
      // ekranda kalıp kullanıcının tekrar denemesine izin veriyoruz.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bağlantı zaman aşımına uğradı. Lütfen tekrar deneyin.')),
      );
    } catch (_) {
      // Oturum sunucu tarafında artık geçersiz (örn. refresh token süresi
      // dolmuş) — normal giriş formuna düşülüyor.
      await _fallbackToLoginForm();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.cachedFullName;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  (name == null || name.isEmpty) ? 'Tekrar hoş geldiniz' : 'Hoş geldin, $name',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                  onPressed: _isLoading ? null : _continue,
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Giriş Yap'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

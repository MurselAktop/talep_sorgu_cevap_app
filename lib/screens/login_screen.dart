import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../services/local_prefs_service.dart';
import '../services/supabase_service.dart';
import 'citizen_guest_menu_screen.dart';
import 'forgot_password_screen.dart';
import 'home_screen.dart';
import 'personnel_register_screen.dart';
import 'register_screen.dart';

/// Hangi giriş bağlamında olunduğunu (vatandaş ya da personel/müdür/admin)
/// takip eder; hem UI metinlerini hem de giriş sonrası rol kontrolünü
/// yönlendirir.
enum _LoginType { vatandas, personel }

/// İlk açılışta "Vatandaş Girişi" / "Personel Girişi" seçimini gösterir;
/// bir seçim yapılınca aynı e-posta/şifre formu (tek kod yolu) o bağlamla
/// gösterilir. Giriş başarılı olduktan hemen sonra, seçilen bağlamla
/// public.users'daki gerçek role uyuşuyor mu diye kontrol edilir —
/// uyuşmuyorsa oturum kapatılıp kullanıcı seçim ekranına geri döndürülür.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _rememberMe = false;
  bool _obscurePassword = true;
  _LoginType? _selectedType;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _selectType(_LoginType type) {
    setState(() => _selectedType = type);
  }

  void _returnToSelection() {
    _emailController.clear();
    _passwordController.clear();
    setState(() {
      _selectedType = null;
      _rememberMe = false;
    });
  }

  Future<void> _submit() async {
    final type = _selectedType;
    if (type == null) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await AuthService.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      final userId = SupabaseService.client.auth.currentUser!.id;
      final profile = await SupabaseService.client
          .from('users')
          .select('role, full_name, is_active')
          .eq('id', userId)
          .single();
      final role = profile['role'] as String;
      final isVatandasAccount = role == 'vatandas';
      final expectedVatandas = type == _LoginType.vatandas;

      // Faz 4 (2026-07-21): pasifleştirilmiş hesap kontrolü. Bu, sadece
      // temiz bir mesaj göstermek için — gerçek güvenlik sınırı RLS/RPC
      // katmanında (current_user_is_active() + RESTRICTIVE politikalar).
      if (profile['is_active'] == false) {
        await SupabaseService.client.auth.signOut();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Hesabınız pasifleştirilmiş. Lütfen yönetici ile iletişime geçin.')),
        );
        _returnToSelection();
        return;
      }

      if (isVatandasAccount != expectedVatandas) {
        await SupabaseService.client.auth.signOut();
        if (!mounted) return;
        // Rol uyuşmazlığı mesajı, hesabın var olup olmadığını/rolünü
        // sızdırmamak için kasıtlı olarak genel tutuluyor (yanlış şifre
        // mesajıyla aynı belirsizlik seviyesinde).
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              expectedVatandas
                  ? 'Giriş bilgileri hatalı. Böyle bir vatandaş hesabı bulunamadı.'
                  : 'Giriş bilgileri hatalı. Böyle bir personel hesabı bulunamadı.',
            ),
          ),
        );
        _returnToSelection();
        return;
      }

      // "Beni Hatırla" tercihi burada, giriş kesinleşmiş (rol/aktiflik
      // kontrolü geçmiş) olduğu için kaydediliyor — erken bir aşamada
      // kaydedilseydi, sonradan reddedilen bir girişte bile yanlışlıkla
      // kalıcı olurdu.
      await LocalPrefsService.setRememberMe(_rememberMe);
      if (_rememberMe) {
        await LocalPrefsService.setCachedFullName(profile['full_name'] as String?);
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomePage()),
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

  // Supabase (GoTrue) hatalarını, kullanıcının anlayacağı kısa Türkçe
  // mesajlara çeviriyoruz. Ham İngilizce mesaj doğrudan gösterilmiyor.
  String _describeAuthError(AuthException e) {
    final message = e.message.toLowerCase();
    if (message.contains('invalid login credentials')) {
      return 'E-posta veya şifre hatalı.';
    }
    if (message.contains('email not confirmed')) {
      return 'E-posta adresiniz henüz onaylanmadı.';
    }
    return 'Giriş yapılamadı. Lütfen bilgilerinizi kontrol edin.';
  }

  @override
  Widget build(BuildContext context) {
    final type = _selectedType;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Giriş Yap'),
        leading: type == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _isLoading ? null : _returnToSelection,
              ),
      ),
      body: Center(
        child: type == null ? _buildTypeSelector() : _buildLoginForm(type),
      ),
    );
  }

  Widget _buildTypeSelector() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              onPressed: () => _selectType(_LoginType.vatandas),
              child: const Text('Vatandaş Girişi'),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              onPressed: () => _selectType(_LoginType.personel),
              child: const Text('Personel Girişi'),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                foregroundColor: Colors.grey.shade700,
                side: BorderSide(color: Colors.grey.shade400),
              ),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CitizenGuestMenuScreen()),
              ),
              child: const Text('Giriş Yapmadan Devam Et'),
            ),
          ],
        ),
      ),
    );
  }

  // Vatandaş ve personel girişleri aynı e-posta/şifre form mantığını
  // paylaşır; sadece başlık ve alttaki kayıt bağlantısı bağlama göre değişir.
  Widget _buildLoginForm(_LoginType type) {
    final isVatandas = type == _LoginType.vatandas;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isVatandas ? 'Vatandaş Girişi' : 'Personel Girişi',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 24),
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
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Şifre',
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: (value) =>
                    (value == null || value.isEmpty) ? 'Şifre girin' : null,
              ),
              CheckboxListTile(
                value: _rememberMe,
                onChanged: _isLoading
                    ? null
                    : (value) => setState(() => _rememberMe = value ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: const Text('Beni Hatırla'),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _isLoading
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ForgotPasswordScreen(),
                            ),
                          ),
                  child: const Text('Şifremi unuttum'),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _isLoading ? null : _submit,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Giriş Yap'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _isLoading
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => isVatandas
                                ? const RegisterScreen()
                                : const PersonnelRegisterScreen(),
                          ),
                        ),
                child: Text(
                  isVatandas
                      ? 'Hesabın yok mu? Kayıt ol'
                      : 'Davet kodun var mı? Personel kaydı yap',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

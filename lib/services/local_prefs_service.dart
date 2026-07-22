import 'package:shared_preferences/shared_preferences.dart';

/// "Beni Hatırla" tercihini ve (yalnızca UI'da hızlı gösterim için) son
/// giriş yapan kullanıcının görünen adını yerelde (cihazda) saklar.
///
/// ÖNEMLİ: Buradaki değerler asla bir güvenlik/yetkilendirme kararı için
/// kullanılmaz — sadece uygulama açılışında hangi ekranın (boş giriş formu
/// mu, "hoş geldin" ekranı mı) gösterileceğini belirler. Gerçek oturum
/// geçerliliği her zaman Supabase'e (sunucuya) sorulur; bkz. AuthGate
/// (main.dart) ve WelcomeBackScreen.
class LocalPrefsService {
  LocalPrefsService._();

  static const _rememberMeKey = 'remember_me';
  static const _cachedFullNameKey = 'cached_full_name';

  static Future<bool> getRememberMe() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_rememberMeKey) ?? false;
  }

  /// `value` false ise önbellekteki adı da temizler — bir sonraki
  /// "hatırlanan" girişte eski bir kullanıcının adı yanlışlıkla gösterilmesin.
  static Future<void> setRememberMe(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberMeKey, value);
    if (!value) {
      await prefs.remove(_cachedFullNameKey);
    }
  }

  static Future<String?> getCachedFullName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_cachedFullNameKey);
  }

  static Future<void> setCachedFullName(String? name) async {
    final prefs = await SharedPreferences.getInstance();
    if (name == null || name.isEmpty) {
      await prefs.remove(_cachedFullNameKey);
    } else {
      await prefs.setString(_cachedFullNameKey, name);
    }
  }
}

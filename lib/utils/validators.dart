import 'phone_input_formatter.dart';

/// Kayıt formlarında (vatandaş + personel) ortak kullanılan alan
/// doğrulayıcıları. Faz 1 kararı gereği tc_no/telefon/il/ilçe tüm kayıt
/// ekranlarında zorunludur; zorunluluk ayrıca veritabanında
/// handle_new_user() trigger'ında da kontrol edilir (form atlanamaz).
class Validators {
  Validators._(); // yalnızca statik üyeler, örneklenmesin

  /// T.C. kimlik numarası doğrulaması: 11 hane, 0 ile başlamaz ve resmi
  /// algoritma sağlaması geçmelidir:
  /// - 10. hane = ((1,3,5,7,9. haneler toplamı) * 7 - (2,4,6,8. haneler toplamı)) mod 10
  /// - 11. hane = (ilk 10 hanenin toplamı) mod 10
  static String? tcNo(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'T.C. kimlik numarası girin';
    if (!RegExp(r'^[1-9][0-9]{10}$').hasMatch(v)) {
      return 'T.C. kimlik numarası 11 haneli olmalı ve 0 ile başlamamalı';
    }
    final d = v.split('').map(int.parse).toList();
    final oddSum = d[0] + d[2] + d[4] + d[6] + d[8];
    final evenSum = d[1] + d[3] + d[5] + d[7];
    final digit10 = ((oddSum * 7 - evenSum) % 10 + 10) % 10;
    final digit11 = d.sublist(0, 10).reduce((a, b) => a + b) % 10;
    if (d[9] != digit10 || d[10] != digit11) {
      return 'Geçersiz T.C. kimlik numarası';
    }
    return null;
  }

  /// Telefon doğrulaması: PhoneInputFormatter'ın ürettiği maskeli metni
  /// (veya ham rakamları) kabul eder, 10 haneli yerel numaranın "5" ile
  /// başlayıp başlamadığını kontrol eder.
  static String? phone(String? value) {
    final local = PhoneInputFormatter.extractLocalDigits(value ?? '');
    if (local.isEmpty) return 'Telefon numarası girin';
    if (!RegExp(r'^5[0-9]{9}$').hasMatch(local)) {
      return 'Geçerli bir cep telefonu girin (+90 5XX XXX XX XX)';
    }
    return null;
  }

  /// Telefonu veritabanına yazmadan önce E.164 biçimine getirir:
  /// "+905XXXXXXXXX" (Faz 2 kararı — bkz. CLAUDE.md).
  static String normalizePhone(String value) {
    return '+90${PhoneInputFormatter.extractLocalDigits(value)}';
  }

  /// Veritabanındaki E.164 telefonu ("+905XXXXXXXXX") profil/kayıt
  /// ekranlarında düzenlenebilir alanı doldururken maskeli görünüme çevirir.
  static String phoneToDisplay(String storedE164) {
    final local = PhoneInputFormatter.extractLocalDigits(storedE164);
    if (local.length != 10) return storedE164; // beklenmeyen biçim, olduğu gibi göster
    return PhoneInputFormatter.maskDigits(local);
  }

  /// Genel zorunlu alan doğrulaması (ilçe gibi serbest metin alanları için).
  static String? requiredField(String? value, String message) {
    return (value == null || value.trim().isEmpty) ? message : null;
  }
}

import 'package:flutter/services.dart';

/// Türkiye cep telefonu alanları için canlı biçimlendirme: kullanıcı sadece
/// 10 haneli yerel numarayı (5 ile başlayan) yazar, alan otomatik olarak
/// "+90 (5XX) XXX XX XX" görünümünü oluşturur. Saklanan E.164 değeri bu
/// görünümden bağımsızdır (bkz. Validators.normalizePhone).
///
/// Basit bir formatter olduğu için imleç her zaman metnin sonuna
/// yerleştirilir; bu yüzden format karakterlerinin (boşluk, parantez)
/// üzerinden backspace ile silme bazen bir hane değil, tek karakter siler
/// — bilinen ve kabul edilen bir sadeleştirme.
class PhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formatted = maskDigits(_extractLocalDigits(newValue.text));
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  /// Ham metinden (formatlanmış veya değil) 10 haneye kadar yerel numarayı
  /// çıkarır: "+90" önekini ve varsa fazladan başındaki "0"ı atar. Yerel
  /// numara her zaman "5" ile başladığından, baştaki "90" her koşulda
  /// bizim eklediğimiz önektir — koşulsuz atılabilir.
  static String _extractLocalDigits(String raw) {
    var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('90')) {
      digits = digits.substring(2);
    }
    if (digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    return digits.length > 10 ? digits.substring(0, 10) : digits;
  }

  /// 10 haneye kadar (kısmi girişler dahil) yerel numarayı
  /// "+90 (5XX) XXX XX XX" biçiminde gruplar.
  static String maskDigits(String digits) {
    if (digits.isEmpty) return '';
    final buffer = StringBuffer('+90 (');
    buffer.write(digits.substring(0, digits.length < 3 ? digits.length : 3));
    if (digits.length >= 3) {
      buffer.write(') ');
      buffer.write(digits.substring(3, digits.length < 6 ? digits.length : 6));
    }
    if (digits.length >= 6) {
      buffer.write(' ');
      buffer.write(digits.substring(6, digits.length < 8 ? digits.length : 8));
    }
    if (digits.length >= 8) {
      buffer.write(' ');
      buffer.write(digits.substring(8));
    }
    return buffer.toString();
  }

  /// extractLocalDigits'i dışarıya (Validators gibi) da açar.
  static String extractLocalDigits(String raw) => _extractLocalDigits(raw);
}

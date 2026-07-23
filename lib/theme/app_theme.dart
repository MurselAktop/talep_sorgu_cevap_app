import 'package:flutter/material.dart';

/// TŞYS'nin merkezi Material 3 teması.
///
/// Bu bir belediye/kurum şikâyet-talep sistemi olduğu için ciddi ve güven
/// verici bir görsel kimlik hedeflenir. Ana tasarım koyu tema (dark theme) —
/// tasarım taslağına göre neredeyse siyah bir taban (#121212) üzerinde biraz
/// daha açık gri kart yüzeyleri (#1E1E1E). Marka/aksiyon rengi (birincil
/// renk), önceki (açık) sürümle aynı kurumsal lacivert tohumdan
/// (`_seedColor`) türetiliyor — Material 3'ün algoritması hem koyu hem açık
/// arka planda okunaklı kalacak bir ton otomatik üretiyor; elle renk
/// seçilmedi. Turuncu, sidebar'daki aktif öğe/CTA rengi olarak
/// KULLANILMIYOR — turuncu zaten `status_badge.dart`'ta "Açık" durumunun
/// anlamı, aynı rengi marka vurgusu için de kullanmak durum rozetleriyle
/// karışıklığa yol açardı.
///
/// **2026-07-22 güncellemesi:** Kullanıcı isteğiyle Ayarlar ekranından
/// değiştirilebilen bir açık tema (`lightTheme`) eklendi — `ThemeController`
/// (main.dart) hangisinin aktif olduğuna karar verir, buradaki iki fonksiyon
/// SADECE `brightness` parametresiyle ayrışan tek bir `_buildTheme`'i
/// paylaşır (kod tekrarı yok).
///
/// Ekranlar kendi AppBar/Card/buton/form stilini YAZMAZ — hepsi buradaki
/// bileşen temalarına güvenir; bu sayede tutarlılık tek kaynaktan sağlanır.
///
/// Bilinçli olarak buraya DAHİL edilmeyenler: `status_badge.dart`'taki durum
/// renkleri ve talep detayındaki "Reddet"/"İptal Et" butonu gibi semantik
/// renkler — bunlar marka kimliğiyle değil ANLAMLA bağlı, `tonalColors()`
/// yardımcı fonksiyonuyla (bkz. status_badge.dart) hem açık hem koyu temaya
/// zaten ayrıca uyarlanıyorlar (bkz. `Theme.of(context).brightness` kontrolü).
class AppTheme {
  AppTheme._();

  /// Kurumsal lacivert.
  static const Color _seedColor = Color(0xFF0B3D63);

  /// Taslaktaki hedef ton — Material 3'ün otomatik koyu yüzey algoritması
  /// yerine, istenen tam hex değerlerini tutturmak için `surface`/
  /// `scaffoldBackgroundColor` elle bindiriliyor.
  static const Color _darkScaffoldBackground = Color(0xFF121212);
  static const Color _darkCardSurface = Color(0xFF1E1E1E);

  static const Color _lightScaffoldBackground = Color(0xFFF4F5F7);
  static const Color _lightCardSurface = Color(0xFFFFFFFF);

  static ThemeData get darkTheme => _buildTheme(Brightness.dark);
  static ThemeData get lightTheme => _buildTheme(Brightness.light);

  static ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scaffoldBackground = isDark ? _darkScaffoldBackground : _lightScaffoldBackground;
    final cardSurface = isDark ? _darkCardSurface : _lightCardSurface;
    final onSurfaceColor = isDark ? Colors.white : Colors.black;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: brightness,
    ).copyWith(surface: scaffoldBackground, surfaceContainerHighest: cardSurface);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBackground,
      textTheme: _textTheme,
      appBarTheme: AppBarThemeData(
        backgroundColor: scaffoldBackground,
        foregroundColor: onSurfaceColor,
        elevation: 0,
        scrolledUnderElevation: 2,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: onSurfaceColor,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
        iconTheme: IconThemeData(color: onSurfaceColor),
        actionsIconTheme: IconThemeData(color: onSurfaceColor),
      ),
      cardTheme: CardThemeData(
        color: cardSurface,
        elevation: isDark ? 0 : 1,
        margin: const EdgeInsets.symmetric(vertical: 6),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: onSurfaceColor.withValues(alpha: isDark ? 0.06 : 0.08)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: onSurfaceColor.withValues(alpha: isDark ? 0.05 : 0.04),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colorScheme.error, width: 2),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide.none,
        backgroundColor: onSurfaceColor.withValues(alpha: isDark ? 0.08 : 0.06),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cardSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? cardSurface : const Color(0xFF323232),
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dividerTheme: DividerThemeData(
        color: onSurfaceColor.withValues(alpha: isDark ? 0.08 : 0.1),
        thickness: 1,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: colorScheme.primary),
      drawerTheme: DrawerThemeData(
        backgroundColor: scaffoldBackground,
        shape: const RoundedRectangleBorder(),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: onSurfaceColor.withValues(alpha: 0.85),
        selectedColor: colorScheme.primary,
        selectedTileColor: colorScheme.primary.withValues(alpha: isDark ? 0.16 : 0.12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  /// Sadece ağırlık/satır yüksekliği farkları — renk KASITLI olarak
  /// belirtilmiyor; `ThemeData` bu sparse TextTheme'i varsayılan
  /// Typography ile `merge()` ediyor (bkz. Flutter kaynağı,
  /// `theme_data.dart`), yani burada set edilmeyen her alan (renk dahil)
  /// varsayılandan geliyor — hiçbir metin stili "kayıp" kalmıyor.
  static const TextTheme _textTheme = TextTheme(
    headlineSmall: TextStyle(fontWeight: FontWeight.w700),
    titleLarge: TextStyle(fontWeight: FontWeight.w700),
    titleMedium: TextStyle(fontWeight: FontWeight.w600),
    titleSmall: TextStyle(fontWeight: FontWeight.w600),
    bodyLarge: TextStyle(height: 1.4),
    bodyMedium: TextStyle(height: 1.4),
    labelLarge: TextStyle(fontWeight: FontWeight.w600),
  );
}

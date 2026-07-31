import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// TŞYS'nin merkezi Material 3 teması.
///
/// Renk kimliği web yönetim paneliyle (`web/` Tailwind blue/slate paleti)
/// hizalıdır: birincil marka mavisi `blue-600` (#2563EB), koyu yüzeyler
/// gray-900/800, açık yüzeyler slate-50. Turuncu marka CTA olarak
/// KULLANILMIYOR — durum rozetlerinde "Açık" ve AI asistan vurgusunda
/// (`aiAccent`) ayrı roller üstleniyor.
///
/// **2026-07-22:** Ayarlar'dan açık/koyu tema (`ThemeController`).
/// **2026-07-31:** Web paneli renk temasına hizalama.
///
/// Ekranlar kendi AppBar/Card/buton/form stilini YAZMAZ — buradaki bileşen
/// temalarına güvenir. Durum renkleri `status_badge.dart`'ta tutulur.
class AppTheme {
  AppTheme._();

  /// Web paneli `blue-600` — birincil marka / CTA.
  static const Color _seedColor = Color(0xFF2563EB);

  /// Arıza Asistanı vurgusu — web `orange-500`.
  static const Color aiAccent = Color(0xFFF97316);

  /// Web gray-900 / gray-800.
  static const Color _darkScaffoldBackground = Color(0xFF111827);
  static const Color _darkCardSurface = Color(0xFF1F2937);

  /// Web slate-50 / white.
  static const Color _lightScaffoldBackground = Color(0xFFF8FAFC);
  static const Color _lightCardSurface = Color(0xFFFFFFFF);

  static ThemeData get darkTheme => _buildTheme(Brightness.dark);
  static ThemeData get lightTheme => _buildTheme(Brightness.light);

  /// Durum / navigasyon çubuğu renkleri. Edge-to-edge Android'de
  /// `ColorScheme.fromSeed`'den gelen yeşilimsi secondary/tertiary tonlar
  /// kenarda ince renkli şerit olarak sızabiliyor — çubukları scaffold ile
  /// birebir eşleyip kontrast zorlamasını kapatıyoruz.
  static SystemUiOverlayStyle systemOverlayStyleFor(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final barColor = isDark ? _darkScaffoldBackground : _lightScaffoldBackground;
    return SystemUiOverlayStyle(
      statusBarColor: barColor,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: barColor,
      systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarDividerColor: barColor,
      systemNavigationBarContrastEnforced: false,
      systemStatusBarContrastEnforced: false,
    );
  }

  static ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scaffoldBackground = isDark ? _darkScaffoldBackground : _lightScaffoldBackground;
    final cardSurface = isDark ? _darkCardSurface : _lightCardSurface;
    final onSurfaceColor = isDark ? Colors.white : Colors.black;
    final overlayStyle = systemOverlayStyleFor(brightness);

    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: brightness,
    ).copyWith(
      // Web paneliyle birebir: light blue-600, dark blue-500.
      primary: isDark ? const Color(0xFF3B82F6) : const Color(0xFF2563EB),
      onPrimary: Colors.white,
      surface: scaffoldBackground,
      surfaceContainerHighest: cardSurface,
      // Kenar/şerit sızıntısını azaltmak için surface türevlerini de
      // scaffold/kart tonlarına sabitle.
      surfaceContainerLowest: scaffoldBackground,
      surfaceContainerLow: cardSurface,
      surfaceContainer: cardSurface,
      surfaceContainerHigh: cardSurface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBackground,
      canvasColor: scaffoldBackground,
      textTheme: _textTheme,
      appBarTheme: AppBarThemeData(
        backgroundColor: scaffoldBackground,
        foregroundColor: onSurfaceColor,
        elevation: 0,
        scrolledUnderElevation: 2,
        centerTitle: false,
        systemOverlayStyle: overlayStyle,
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

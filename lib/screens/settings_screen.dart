import 'package:flutter/material.dart';

import '../theme/theme_controller.dart';
import '../widgets/app_nav_route.dart';
import '../widgets/navigation_shell.dart';
import 'change_password_screen.dart';

/// Ayarlar hub ekranı (2026-07-22). Eskiden "Ayarlar" sidebar öğesi
/// doğrudan `ChangePasswordScreen`'e gidiyordu (tek ayar oydu); artık
/// başlıklı bölümlere ayrıldı: Hesap (şifre değiştir) ve Görünüm
/// (açık/koyu tema). Yeni bir ayar eklendiğinde buraya yeni bir bölüm
/// olarak eklenir — `NavigationShell` içinde normal bir üst düzey ekran.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return NavigationShell(
      currentRoute: AppNavRoute.settings,
      title: 'Ayarlar',
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const _SectionHeader(title: 'Hesap'),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Şifre Değiştir'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
            ),
          ),
          const Divider(height: 24),
          const _SectionHeader(title: 'Görünüm'),
          const _ThemeModeTile(),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

/// Açık/koyu tema anahtarı — `ThemeController.mode`'u dinleyip aynı
/// controller üzerinden günceller (bkz. main.dart).
class _ThemeModeTile extends StatelessWidget {
  const _ThemeModeTile();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, mode, _) {
        final isDark = mode == ThemeMode.dark;
        return ListTile(
          leading: Icon(isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined),
          title: const Text('Koyu Tema'),
          subtitle: Text(isDark ? 'Açık: koyu renk paleti kullanılıyor' : 'Kapalı: açık renk paleti kullanılıyor'),
          trailing: Switch(
            value: isDark,
            onChanged: (value) => ThemeController.setMode(value ? ThemeMode.dark : ThemeMode.light),
          ),
          onTap: () => ThemeController.setMode(isDark ? ThemeMode.light : ThemeMode.dark),
        );
      },
    );
  }
}

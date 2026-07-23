import 'package:flutter/material.dart';

/// `users.role` değerine göre ayırt edici bir ikon döndürür (2026-07-22).
/// Sidebar profil kartı (`navigation_shell.dart`) ve Ana Sayfa karşılama
/// bölümü (`home_screen.dart`) aynı ikonu kullanır — rol etiketleri
/// (Türkçe metin) her ekranın kendi küçük map'inde kalmaya devam ediyor
/// (bu dosya sadece ikonu paylaşıyor, metin çevirisini değil).
IconData roleIcon(String role) {
  switch (role) {
    case 'admin':
      return Icons.admin_panel_settings_outlined;
    case 'mudur':
      return Icons.supervisor_account_outlined;
    case 'personel':
      return Icons.badge_outlined;
    default:
      return Icons.person_outline;
  }
}

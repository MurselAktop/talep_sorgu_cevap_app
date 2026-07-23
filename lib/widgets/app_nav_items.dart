import 'package:flutter/material.dart';

import '../screens/admin_department_screen.dart';
import '../screens/admin_email_change_requests_screen.dart';
import '../screens/admin_invite_screen.dart';
import '../screens/admin_stats_screen.dart';
import '../screens/admin_users_screen.dart';
import '../screens/home_screen.dart';
import '../screens/manager_stats_screen.dart';
import '../screens/messages_screen.dart';
import '../screens/my_requests_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/request_create_screen.dart';
import '../screens/request_list_screen.dart';
import '../screens/settings_screen.dart';
import 'app_nav_route.dart';

/// Sidebar/drawer'da gösterilen tek bir menü öğesi. `builder` "Çıkış Yap"
/// için bilinçli olarak `null` — o öğe bir ekrana gitmez, `NavigationShell`
/// içinde ayrıca (signOut çağrısı olarak) ele alınır.
///
/// **2026-07-22 güncellemesi:** Eskiden burada bir `pushOnTop` ayrımı vardı
/// (üst düzey ekranlar `pushReplacement`, "Ayarlar" gibi tekil istisnalar
/// `push`). Geri tuşu davranışı netleştirilince ("sadece Ana Sayfa'dayken
/// çıkış onayı, diğer her ekranda bir önceki ekrana dön") bu ayrıma gerek
/// kalmadı — `NavigationShell` artık TÜM öğeler için `push` kullanıyor;
/// `PopScope`, Navigator yığınının gerçekten boşalıp boşalmadığına
/// (`canPop()`) bakarak çıkış onayını sadece kökte (Ana Sayfa) tetikliyor.
class AppNavItem {
  final AppNavRoute id;
  final String label;
  final IconData icon;

  /// İkonun (seçili değilken) rengi — 2026-07-23 "daha renkli ikonlar"
  /// isteğiyle eklendi. Her öğeye farklı, birbirinden ayırt edilebilir bir
  /// renk atanır; öğe seçiliyken `navigation_shell.dart` bunun yerine tema
  /// accent rengini kullanır (aktif öğe vurgusu bozulmasın diye).
  final Color color;
  final WidgetBuilder? builder;

  const AppNavItem({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
    this.builder,
  });
}

/// Rol bazlı, TEK ortak menü içeriği — hem geniş ekrandaki kalıcı sidebar hem
/// dar ekrandaki Drawer bu listeyi kullanır (`NavigationShell`), böylece
/// "hangi rolde hangi öğe görünüyor" kararı iki yerde ayrı ayrı yazılmaz.
///
/// Görünürlük kuralları CLAUDE.md'deki rol tanımlarıyla aynı: "Gelen
/// Talepler" personel/müdür/admin'e (`canViewIncoming`), davet/birim/kullanıcı
/// yönetimi sadece admin'e, "İstatistikler" admin VEYA müdüre (hedef ekran
/// role göre değişir — `get_admin_stats`/`get_manager_stats` RPC ayrımıyla
/// aynı "rol dallanmasını Dart'a sızdırma" ilkesi burada da geçerli, sadece
/// hangi EKRANA gidileceği değişiyor).
///
/// "Ayarlar" artık kendi hub ekranına (`settings_screen.dart`: şifre
/// değiştirme + açık/koyu tema bölümleri) gidiyor. "E-posta Değişiklik
/// Talepleri" sadece admin'e görünür — personel/vatandaş/müdürün
/// `profile_screen.dart`'tan gönderdiği e-posta değişikliği taleplerini
/// onaylama/reddetme ekranı.
List<AppNavItem> buildNavItems({
  required bool isAdmin,
  required bool isMudur,
  required bool canViewIncoming,
}) {
  return [
    AppNavItem(
      id: AppNavRoute.home,
      label: 'Ana Sayfa',
      icon: Icons.home_outlined,
      color: Colors.blue,
      builder: (_) => const HomePage(),
    ),
    AppNavItem(
      id: AppNavRoute.createRequest,
      label: 'Talep Oluştur',
      icon: Icons.add_circle_outline,
      color: Colors.green,
      builder: (_) => const RequestCreateScreen(),
    ),
    AppNavItem(
      id: AppNavRoute.myRequests,
      label: 'Taleplerim',
      icon: Icons.assignment_outlined,
      color: Colors.orange,
      builder: (_) => const MyRequestsScreen(),
    ),
    if (canViewIncoming)
      AppNavItem(
        id: AppNavRoute.incomingRequests,
        label: 'Gelen Talepler',
        icon: Icons.move_to_inbox_outlined,
        color: Colors.purple,
        builder: (_) => const RequestListScreen(),
      ),
    // Faz 7 (2026-07-23) — kurum-içi DM: personel↔kendi birim müdürü,
    // müdür↔admin. Vatandaş kapsam dışı (kullanıcı kararı), bu yüzden AYNI
    // `canViewIncoming` koşulu (personel/müdür/admin) yeniden kullanılıyor.
    if (canViewIncoming)
      AppNavItem(
        id: AppNavRoute.messages,
        label: 'Mesajlar',
        icon: Icons.chat_bubble_outline,
        color: Colors.amber,
        builder: (_) => const MessagesScreen(),
      ),
    if (isAdmin)
      AppNavItem(
        id: AppNavRoute.invite,
        label: 'Davet Kodu Oluştur',
        icon: Icons.key_outlined,
        color: Colors.teal,
        builder: (_) => const AdminInviteScreen(),
      ),
    if (isAdmin)
      AppNavItem(
        id: AppNavRoute.departments,
        label: 'Birim Yönetimi',
        icon: Icons.apartment_outlined,
        color: Colors.brown,
        builder: (_) => const AdminDepartmentScreen(),
      ),
    if (isAdmin)
      AppNavItem(
        id: AppNavRoute.users,
        label: 'Kullanıcı Yönetimi',
        icon: Icons.people_outline,
        color: Colors.indigo,
        builder: (_) => const AdminUsersScreen(),
      ),
    if (isAdmin || isMudur)
      AppNavItem(
        id: AppNavRoute.stats,
        label: 'İstatistikler',
        icon: Icons.bar_chart_outlined,
        color: Colors.pink,
        builder: (_) => isAdmin ? const AdminStatsScreen() : const ManagerStatsScreen(),
      ),
    if (isAdmin)
      AppNavItem(
        id: AppNavRoute.emailChangeRequests,
        label: 'E-posta Değişiklik Talepleri',
        icon: Icons.mark_email_read_outlined,
        color: Colors.cyan,
        builder: (_) => const AdminEmailChangeRequestsScreen(),
      ),
    AppNavItem(
      id: AppNavRoute.profile,
      label: 'Profilim',
      icon: Icons.person_outline,
      color: Colors.deepPurple,
      builder: (_) => const ProfileScreen(),
    ),
    AppNavItem(
      id: AppNavRoute.settings,
      label: 'Ayarlar',
      icon: Icons.settings_outlined,
      color: Colors.blueGrey,
      builder: (_) => const SettingsScreen(),
    ),
    AppNavItem(
      id: AppNavRoute.logout,
      label: 'Çıkış Yap',
      icon: Icons.logout,
      color: Colors.red.shade300,
    ),
  ];
}

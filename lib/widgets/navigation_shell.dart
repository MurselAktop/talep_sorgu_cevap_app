import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/login_screen.dart';
import '../screens/notifications_screen.dart';
import '../services/supabase_service.dart';
import 'app_nav_items.dart';
import 'app_nav_route.dart';
import 'role_icon.dart';
import 'user_avatar.dart';

const Map<String, String> _shellRoleLabels = {
  'vatandas': 'Vatandaş',
  'personel': 'Personel',
  'mudur': 'Müdür',
  'admin': 'Admin',
};

/// Sidebar'ın kalıcı olarak göründüğü (web/geniş ekran) ile Drawer'a
/// dönüştüğü (mobil/dar ekran) genişlik eşiği.
const double _wideBreakpoint = 800;
const double _sidebarWidth = 280;

/// TŞYS'nin TEK merkezi navigasyon iskeleti. Her "üst düzey" ekran (Ana
/// Sayfa, Talep Oluştur, Taleplerim, Gelen Talepler, admin/müdür ekranları,
/// Profilim, Ayarlar) kendi `Scaffold`'unu YAZMAZ — bunun yerine bu widget'ı
/// döndürür; `body` sadece o ekranın asıl içeriğidir.
///
/// Responsive davranış (`LayoutBuilder`, genişlik ≥ 800px "geniş" sayılır):
/// - Geniş ekran: sidebar kalıcı olarak solda (Row + Expanded), Drawer YOK.
/// - Dar ekran: aynı menü içeriği bir Drawer'a taşınır, AppBar otomatik
///   hamburger ikonu gösterir (Scaffold'un yerleşik davranışı — `drawer` set
///   edildiğinde ve `leading` boş olduğunda kendiliğinden ekleniyor).
///
/// Menü öğelerinin İÇERİĞİ (`buildNavItems`) `app_nav_items.dart`'ta paylaşılan
/// TEK bir listede tutuluyor — burada sadece o listeyi render ediyoruz, kod
/// tekrarı yok.
///
/// Giriş yapılmamışsa (örn. anonim vatandaşın `RequestCreateScreen`'i) sidebar/
/// drawer hiç gösterilmez, sade bir `AppBar` + `body`'e düşülür — çünkü rol
/// bilgisi yok, gösterilecek bir menü de yok.
class NavigationShell extends StatefulWidget {
  const NavigationShell({
    super.key,
    required this.currentRoute,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
  });

  final AppNavRoute currentRoute;
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;

  @override
  State<NavigationShell> createState() => _NavigationShellState();
}

class _NavigationShellState extends State<NavigationShell> {
  static SupabaseClient get _client => SupabaseService.client;

  /// Dar ekranda (Drawer modu) drawer'ı kapatmak için kullanılır. Drawer,
  /// Navigator yığınına bir route PUSH etmediğinden (kendi `ScaffoldState`
  /// animasyon controller'ıyla açılıp kapanır) — `_buildNavList` bu State'in
  /// KENDİ metodu olduğu için, içindeki bare `context` her zaman bu State'in
  /// (Scaffold'un ATASI, altındaki Drawer değil) context'ine işaret eder ve
  /// `Scaffold.of(context)` bu yüzden Scaffold'u BULAMAZ (yukarı doğru arar,
  /// Drawer aşağıda kalır). `GlobalKey<ScaffoldState>`, context hiyerarşisine
  /// bağlı olmayan güvenilir bir alternatif.
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  bool _isLoadingProfile = true;
  String? _fullName;
  String? _email;
  String? _avatarPath;
  String _role = 'vatandas';
  bool _isAdmin = false;
  bool _isMudur = false;
  bool _canViewIncoming = false;
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadUnreadCount();
  }

  Future<void> _loadProfile() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _isLoadingProfile = false);
      return;
    }
    try {
      final profile = await _client
          .from('users')
          .select('role, full_name, email, avatar_url')
          .eq('id', userId)
          .single();
      final role = profile['role'] as String;
      if (!mounted) return;
      setState(() {
        _fullName = profile['full_name'] as String?;
        _email = profile['email'] as String?;
        _avatarPath = profile['avatar_url'] as String?;
        _role = role;
        _isAdmin = role == 'admin';
        _isMudur = role == 'mudur';
        _canViewIncoming = role == 'personel' || role == 'mudur' || role == 'admin';
      });
    } catch (_) {
      // Profil okunamazsa sidebar minimal (rol bazlı öğeler olmadan) kalır;
      // ekranın asıl içeriği (widget.body) bundan etkilenmez.
    } finally {
      if (mounted) setState(() => _isLoadingProfile = false);
    }
  }

  /// `home_screen.dart`'taki (eski) bildirim sayacı ile aynı desen — sessizce
  /// yutulur, sadece zil ikonundaki rozeti besler.
  Future<void> _loadUnreadCount() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final count = await _client
          .from('notifications')
          .count(CountOption.exact)
          .eq('is_read', false);
      if (mounted) setState(() => _unreadCount = count);
    } catch (_) {
      // Sessizce yutulur.
    }
  }

  Future<void> _signOut() async {
    try {
      await _client.auth.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Çıkış yapılamadı. Lütfen tekrar deneyin.')),
      );
    }
  }

  /// Sidebar/drawer'daki bir öğeye tıklanınca çağrılır. **2026-07-22
  /// güncellemesi:** artık HER öğe için normal `push` kullanılıyor (eskiden
  /// üst düzey hedefler `pushReplacement` ile değiştiriliyordu). Sebep: geri
  /// tuşu davranışı netleştirildi — "sadece Ana Sayfa'dayken çıkış onayı,
  /// diğer her ekranda bir önceki ekrana dön" isteği, Navigator'ın normal
  /// push/pop yığınıyla ZATEN doğal olarak sağlanıyor (bkz. `build()`'teki
  /// `PopScope`, `canPop()` kontrolü). Ana Sayfa'ya tekrar tıklanması hâlâ
  /// yığına yeni bir sayfa eklemez — `if (item.id == widget.currentRoute)`
  /// kontrolü zaten aynı ekrana tekrar gitmeyi engelliyor.
  void _handleNavTap(AppNavItem item, {required bool closeDrawerFirst}) {
    if (closeDrawerFirst) _scaffoldKey.currentState?.closeDrawer();

    if (item.id == AppNavRoute.logout) {
      _signOut();
      return;
    }
    if (item.id == widget.currentRoute) return;

    Navigator.of(context).push(MaterialPageRoute(builder: item.builder!));
  }

  Widget _buildProfileCard() {
    final roleLabel = _isAdmin
        ? _shellRoleLabels['admin']!
        : _isMudur
        ? _shellRoleLabels['mudur']!
        : (_canViewIncoming ? _shellRoleLabels['personel']! : _shellRoleLabels['vatandas']!);
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Row(
        children: [
          UserAvatar(avatarPath: _avatarPath, fullName: _fullName, radius: 24),
          const SizedBox(width: 12),
          Expanded(
            child: _isLoadingProfile
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _fullName ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      Row(
                        children: [
                          Icon(roleIcon(_role), size: 13, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 4),
                          Text(
                            roleLabel,
                            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary),
                          ),
                        ],
                      ),
                      Text(
                        _email ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: onSurface.withValues(alpha: 0.5)),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavList({required bool inDrawer}) {
    final items = buildNavItems(
      isAdmin: _isAdmin,
      isMudur: _isMudur,
      canViewIncoming: _canViewIncoming,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildProfileCard(),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              for (final item in items)
                if (item.id == AppNavRoute.logout) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Divider(height: 1),
                  ),
                  ListTile(
                    leading: Icon(item.icon, color: item.color),
                    title: Text(item.label, style: TextStyle(color: item.color)),
                    onTap: () => _handleNavTap(item, closeDrawerFirst: inDrawer),
                  ),
                ] else
                  ListTile(
                    // Seçili öğede accent rengi (aktif vurgu) korunuyor, diğer
                    // öğelerde her birine özgü renk kullanılıyor (2026-07-23
                    // "daha renkli ikonlar" isteği).
                    leading: Icon(
                      item.icon,
                      color: item.id == widget.currentRoute
                          ? Theme.of(context).colorScheme.primary
                          : item.color,
                    ),
                    title: Text(item.label),
                    selected: item.id == widget.currentRoute,
                    onTap: () => _handleNavTap(item, closeDrawerFirst: inDrawer),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
    if (!mounted) return;
    _loadUnreadCount();
  }

  /// Sadece Navigator yığınının KÖKÜNDE (yani `canPop() == false` —
  /// pratikte bu her zaman Ana Sayfa'dır, çünkü giriş sonrası ilk açılan
  /// ekran odur ve sidebar/drawer'daki tüm öğeler artık `push` kullanıyor,
  /// bkz. `_handleNavTap`) çağrılır; `build()`'teki `PopScope.canPop`
  /// bunun dışındaki HER ekranda `true` olduğu için fiziksel geri tuşu o
  /// durumlarda zaten normal `Navigator.pop()` ile bir önceki ekrana döner
  /// ve bu metot hiç tetiklenmez.
  Future<void> _confirmExitAndPop() async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Uygulamadan Çık'),
        content: const Text('Çıkış yapmak istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Hayır'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Evet'),
          ),
        ],
      ),
    );
    if (shouldExit == true) {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = _client.auth.currentUser != null;

    // Anonim/misafir akışları (örn. giriş yapmadan talep oluşturma) için
    // sidebar/drawer'ın hiçbir anlamı yok — sade bir Scaffold'a düşülür.
    // Bu akışta zaten normal bir `push` ile gelinmiştir, geri tuşu doğal
    // olarak önceki ekrana döner — PopScope koruması gerekmez.
    if (!isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title), actions: widget.actions),
        body: widget.body,
        floatingActionButton: widget.floatingActionButton,
      );
    }

    return PopScope(
      canPop: Navigator.of(context).canPop(),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _confirmExitAndPop();
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= _wideBreakpoint;

          final appBar = AppBar(
            title: Text(widget.title),
            actions: [
              ...?widget.actions,
              IconButton(
                icon: Badge(
                  backgroundColor: Colors.red,
                  label: Text('$_unreadCount'),
                  isLabelVisible: _unreadCount > 0,
                  child: const Icon(Icons.notifications_outlined),
                ),
                tooltip: 'Bildirimler',
                onPressed: _openNotifications,
              ),
            ],
          );

          if (isWide) {
            return Scaffold(
              appBar: appBar,
              body: Row(
                children: [
                  SizedBox(
                    width: _sidebarWidth,
                    child: Material(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      child: _buildNavList(inDrawer: false),
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: widget.body),
                ],
              ),
              floatingActionButton: widget.floatingActionButton,
            );
          }

          return Scaffold(
            key: _scaffoldKey,
            appBar: appBar,
            drawer: Drawer(child: _buildNavList(inDrawer: true)),
            body: widget.body,
            floatingActionButton: widget.floatingActionButton,
          );
        },
      ),
    );
  }
}

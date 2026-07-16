import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';
import 'admin_invite_screen.dart';
import 'login_screen.dart';
import 'my_requests_screen.dart';
import 'notifications_screen.dart';
import 'request_create_screen.dart';
import 'request_list_screen.dart';

/// Geçici ana ekran (placeholder). Talep listeleme ekranı henüz bu ekranın
/// yerini almadı, sadece "Gelen Talepler"/"Taleplerim" butonlarıyla bağlandı.
/// Giriş yapmış herkese (vatandaş/personel/müdür/admin fark etmeksizin)
/// "Talep Oluştur" ve "Taleplerim" butonları gösteriliyor; requester_type
/// ayrımı RequestCreateScreen içinde, "Taleplerim"in içeriği ise RLS'in
/// created_by = auth.uid() kuralıyla role'e bakılmaksızın zaten
/// belirleniyor. "Gelen Talepler" butonu yalnızca personel/müdür/admin için,
/// "Davet Kodu Oluştur" butonu yalnızca admin için gösteriliyor (bkz.
/// CLAUDE.md yol haritası, madde 5).
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _isLoadingRole = true;
  bool _canViewRequestList = false;
  bool _isAdmin = false;
  String? _fullName;
  int _unreadNotificationCount = 0;

  @override
  void initState() {
    super.initState();
    _loadRole();
    _loadUnreadNotificationCount();
  }

  Future<void> _loadRole() async {
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _isLoadingRole = false);
      return;
    }

    try {
      final profile = await SupabaseService.client
          .from('users')
          .select('role, full_name')
          .eq('id', userId)
          .single();
      final role = profile['role'] as String;
      if (mounted) {
        setState(() {
          _canViewRequestList = role == 'personel' || role == 'mudur' || role == 'admin';
          _isAdmin = role == 'admin';
          _fullName = profile['full_name'] as String?;
        });
      }
    } catch (_) {
      // Rol okunamazsa buton gösterilmez; ekranın geri kalanı çalışmaya devam eder.
    } finally {
      if (mounted) setState(() => _isLoadingRole = false);
    }
  }

  /// Sayaç yalnızca zil ikonundaki rozeti besler; okunamazsa sessizce
  /// yutulur, ekranın geri kalanı etkilenmez.
  Future<void> _loadUnreadNotificationCount() async {
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final count = await SupabaseService.client
          .from('notifications')
          .count(CountOption.exact)
          .eq('is_read', false);
      if (mounted) setState(() => _unreadNotificationCount = count);
    } catch (_) {
      // Sessizce yutulur, yukarıdaki dokümantasyona bakın.
    }
  }

  Future<void> _signOut() async {
    try {
      await SupabaseService.client.auth.signOut();
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

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = SupabaseService.client.auth.currentUser != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('TŞYS — Talep ve Şikâyet Yönetim Sistemi'),
        actions: [
          if (isLoggedIn)
            IconButton(
              icon: Badge(
                backgroundColor: Colors.red,
                label: Text('$_unreadNotificationCount'),
                isLabelVisible: _unreadNotificationCount > 0,
                child: const Icon(Icons.notifications),
              ),
              tooltip: 'Bildirimler',
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                );
                if (!mounted) return;
                _loadUnreadNotificationCount();
              },
            ),
          if (isLoggedIn)
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Çıkış Yap',
              onPressed: _signOut,
            ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoggedIn) ...[
              if (_isLoadingRole)
                const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (_fullName != null)
                Text(
                  'Hoşgeldin, $_fullName',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              const SizedBox(height: 16),
            ],
            const Text('Talep ve Şikâyet Yönetim Sistemi'),
            if (isLoggedIn) ...[
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const RequestCreateScreen()),
                ),
                child: const Text('Talep Oluştur'),
              ),
            ],
            if (isLoggedIn) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MyRequestsScreen()),
                ),
                child: const Text('Taleplerim'),
              ),
            ],
            if (!_isLoadingRole && _canViewRequestList) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const RequestListScreen()),
                ),
                child: const Text('Gelen Talepler'),
              ),
            ],
            if (!_isLoadingRole && _isAdmin) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AdminInviteScreen()),
                ),
                child: const Text('Davet Kodu Oluştur'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

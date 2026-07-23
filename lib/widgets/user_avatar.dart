import 'package:flutter/material.dart';

import '../services/supabase_service.dart';

/// Kullanıcının profil fotoğrafını (varsa) ya da baş harfini gösteren
/// paylaşılan avatar widget'ı (2026-07-22). `avatars` bucket'ı private
/// olduğu için [avatarPath] doğrudan gösterilemez — her build'de kısa ömürlü
/// (1 saat) bir `createSignedUrl` alınır; `request_detail_screen.dart`'taki
/// ek görüntüleme deseniyle aynı yaklaşım. Fotoğraf yoksa veya
/// yüklenemezse sessizce baş harf rozetine düşülür — bu ikincil bir görsel
/// detay, hata göstermek gereksiz.
class UserAvatar extends StatefulWidget {
  const UserAvatar({
    super.key,
    required this.avatarPath,
    required this.fullName,
    this.radius = 24,
    this.onTap,
  });

  final String? avatarPath;
  final String? fullName;
  final double radius;
  final VoidCallback? onTap;

  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar> {
  String? _signedUrl;

  @override
  void initState() {
    super.initState();
    _loadSignedUrl();
  }

  @override
  void didUpdateWidget(UserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatarPath != widget.avatarPath) _loadSignedUrl();
  }

  Future<void> _loadSignedUrl() async {
    final path = widget.avatarPath;
    if (path == null || path.isEmpty) {
      if (mounted) setState(() => _signedUrl = null);
      return;
    }
    try {
      final url = await SupabaseService.client.storage.from('avatars').createSignedUrl(path, 3600);
      if (mounted) setState(() => _signedUrl = url);
    } catch (_) {
      if (mounted) setState(() => _signedUrl = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final trimmedName = widget.fullName?.trim() ?? '';
    final initial = trimmedName.isNotEmpty ? trimmedName[0].toUpperCase() : '?';

    final avatar = CircleAvatar(
      radius: widget.radius,
      backgroundColor: Theme.of(context).colorScheme.primary,
      backgroundImage: _signedUrl != null ? NetworkImage(_signedUrl!) : null,
      child: _signedUrl == null
          ? Text(
              initial,
              style: TextStyle(
                fontSize: widget.radius * 0.75,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            )
          : null,
    );

    if (widget.onTap == null) return avatar;
    return InkWell(
      borderRadius: BorderRadius.circular(widget.radius),
      onTap: widget.onTap,
      child: avatar,
    );
  }
}

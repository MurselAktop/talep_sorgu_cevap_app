import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/turkiye_ilceler.dart';
import '../constants/turkiye_iller.dart';
import '../services/supabase_service.dart';
import '../utils/phone_input_formatter.dart';
import '../utils/validators.dart';
import '../widgets/app_nav_route.dart';
import '../widgets/navigation_shell.dart';
import '../widgets/role_icon.dart';
import '../widgets/star_rating.dart';
import '../widgets/user_avatar.dart';

const Map<String, String> _profileRoleLabels = {
  'vatandas': 'Vatandaş',
  'personel': 'Personel',
  'mudur': 'Müdür',
  'admin': 'Admin',
};

const Map<String, String> _emailRequestStatusLabels = {
  'beklemede': 'Admin onayı bekleniyor',
  'onaylandi': 'Onaylandı',
  'reddedildi': 'Reddedildi',
};

/// Kullanıcının kendi hesap bilgilerini görüp düzenlediği ekran (Faz 2,
/// 2026-07-22'de profil fotoğrafı + e-posta değişikliği talebiyle
/// genişletildi). full_name/phone/il/ilce/avatar düzenlenebilir; e-posta
/// artık DOĞRUDAN düzenlenemez — admin onayı gerektiren bir talep akışına
/// çevrildi (bkz. `request_email_change`/`admin_review_email_change` RPC'leri,
/// migration'daki gerekçe). role/department salt okunurdur — role/
/// department_id zaten RLS'in `kendi_profilini_güncelleyebilir`
/// politikasında `WITH CHECK` ile korunuyor. tc_no bu ekranda hiç
/// gösterilmiyor (Faz 1 kararı: sadece kullanıcının kendisi + admin, ayrı
/// bir users_private tablosunda).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const _networkTimeout = Duration(seconds: 15);
  static SupabaseClient get _client => SupabaseService.client;

  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  String? _selectedIl;
  String? _selectedIlce;

  bool _isLoadingProfile = true;
  bool _isSaving = false;
  bool _isUploadingAvatar = false;
  String? _loadError;
  String _email = '';
  String _role = 'vatandas';
  String _roleLabel = '';
  String _departmentLabel = 'Yok';
  String? _avatarPath;
  Map<String, dynamic>? _pendingEmailRequest;
  Map<String, dynamic>? _personnelRating;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      setState(() {
        _isLoadingProfile = false;
        _loadError = 'Oturum bulunamadı.';
      });
      return;
    }

    try {
      final profile = await _client
          .from('users')
          .select('full_name, email, phone, il, ilce, role, department_id, avatar_url')
          .eq('id', userId)
          .single()
          .timeout(_networkTimeout);

      String departmentLabel = 'Yok';
      // department_id, departments.id gibi bigint'tir (diğer tabloların
      // aksine uuid DEĞİL) — "as String?" cast'i vatandaşta (her zaman null
      // olduğu için) sessizce geçiyor ama admin/personel/müdürde (gerçek bir
      // int değeri olduğu için) TypeError fırlatıp bu profili yükleyemiyordu.
      final departmentId = profile['department_id'];
      if (departmentId != null) {
        final department = await _client
            .from('departments')
            .select('name')
            .eq('id', departmentId)
            .single()
            .timeout(_networkTimeout);
        departmentLabel = department['name'] as String? ?? 'Yok';
      }

      final rawPhone = profile['phone'] as String?;
      final il = profile['il'] as String?;
      final ilce = profile['ilce'] as String?;
      if (!mounted) return;
      setState(() {
        _fullNameController.text = profile['full_name'] as String? ?? '';
        _phoneController.text = (rawPhone == null || rawPhone.isEmpty)
            ? ''
            : Validators.phoneToDisplay(rawPhone);
        _selectedIl = il;
        _selectedIlce = (il != null && (turkiyeIlceleri[il]?.contains(ilce) ?? false)) ? ilce : null;
        _email = profile['email'] as String? ?? '';
        _role = profile['role'] as String? ?? '';
        _roleLabel = _profileRoleLabels[_role] ?? _role;
        _departmentLabel = departmentLabel;
        _avatarPath = profile['avatar_url'] as String?;
        _isLoadingProfile = false;
      });
      _loadPendingEmailRequest(userId);
      if (_role == 'personel') _loadPersonnelRating();
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _isLoadingProfile = false;
        _loadError =
            'Bağlantı zaman aşımına uğradı. Lütfen tekrar deneyin.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingProfile = false;
        _loadError = 'Profil bilgileri yüklenemedi. Lütfen tekrar deneyin.';
      });
    }
  }

  /// En son e-posta değişikliği talebini gösterir (`beklemede` ise admin
  /// onayı beklendiğini, `reddedildi` ise son sonucu bildirir) — sessizce
  /// yutulur, bu ikincil bir bilgi.
  Future<void> _loadPendingEmailRequest(String userId) async {
    try {
      final rows = await _client
          .from('email_change_requests')
          .select('id, requested_email, status')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(1);
      if (!mounted || rows.isEmpty) return;
      final latest = rows.first;
      if (latest['status'] == 'beklemede') {
        setState(() => _pendingEmailRequest = latest);
      }
    } catch (_) {
      // Sessizce yutulur.
    }
  }

  /// Faz 6 (2026-07-23) — personelin kendi ortalama puanı, avatarın altında
  /// küçük bir yıldız rozeti olarak gösterilir. `get_personnel_ratings()`
  /// personel rolündeki çağıran için sadece kendi satırını döndürür (bkz.
  /// migration'daki gerekçe). İkincil bir bilgi olduğundan hata sessizce yutulur.
  Future<void> _loadPersonnelRating() async {
    try {
      final rows = await _client.rpc('get_personnel_ratings') as List;
      if (!mounted || rows.isEmpty) return;
      setState(() => _personnelRating = Map<String, dynamic>.from(rows.first as Map));
    } catch (_) {
      // Sessizce yutulur.
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    setState(() => _isSaving = true);
    try {
      // role/department_id BİLİNÇLİ olarak payload'a dahil edilmiyor —
      // RLS zaten self-update ile değişmelerini engelliyor, ama gereksiz
      // bir reddedilmeyi önlemek için burada hiç gönderilmiyorlar.
      await _client
          .from('users')
          .update({
            'full_name': _fullNameController.text.trim(),
            'phone': Validators.normalizePhone(_phoneController.text),
            'il': _selectedIl,
            'ilce': _selectedIlce,
          })
          .eq('id', userId)
          .timeout(_networkTimeout);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil bilgileriniz güncellendi.')),
      );
    } on TimeoutException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bağlantı zaman aşımına uğradı. Lütfen tekrar deneyin.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Güncelleme başarısız oldu. Lütfen tekrar deneyin.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    final XFile? picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null) return;

    setState(() => _isUploadingAvatar = true);
    try {
      final Uint8List bytes = await picked.readAsBytes();
      final mimeType = _guessImageMimeType(picked.name);
      final storagePath = '$userId/avatar';

      await _client.storage
          .from('avatars')
          .uploadBinary(
            storagePath,
            bytes,
            fileOptions: FileOptions(contentType: mimeType, upsert: true),
          );

      await _client.from('users').update({'avatar_url': storagePath}).eq('id', userId);

      if (!mounted) return;
      setState(() => _avatarPath = storagePath);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil fotoğrafınız güncellendi.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fotoğraf yüklenemedi. Lütfen tekrar deneyin.')),
      );
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  /// Profil fotoğrafına (küçük düzenle ikonuna değil, fotoğrafın kendisine)
  /// dokununca büyük ekranda gösterir — `request_detail_screen.dart`'taki
  /// `_showImagePreview` ile AYNI görsel dil (siyah zemin, `InteractiveViewer`
  /// ile yakınlaştırılabilir, sağ üstte kapatma ikonu).
  Future<void> _showAvatarFullScreen() async {
    final path = _avatarPath;
    if (path == null || path.isEmpty) return;
    try {
      final signedUrl = await _client.storage.from('avatars').createSignedUrl(path, 3600);
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(12),
          child: Stack(
            alignment: Alignment.topRight,
            children: [
              InteractiveViewer(child: Image.network(signedUrl)),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          ),
        ),
      );
    } catch (_) {
      // Sessizce yutulur — büyük önizleme ikincil bir özellik.
    }
  }

  String _guessImageMimeType(String fileName) {
    switch (fileName.toLowerCase().split('.').last) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  /// GERÇEK KÖK NEDEN (bkz. `admin_department_screen.dart`'taki AYNI hatanın
  /// teşhisi, 2026-07-22, `flutter attach` ile tam stack trace yakalanarak
  /// doğrulanmıştı: "A TextEditingController was used after being disposed").
  /// Bu dialog da eskiden `TextEditingController`'ı yerel bir değişkende
  /// tutup `await showDialog(...)` döndükten HEMEN sonra elle `dispose()`
  /// ediyordu — `showDialog()`'un Future'ı `Navigator.pop()` çağrıldığı ANDA
  /// tamamlanır ama dialog kapanış animasyonu boyunca widget'ları hâlâ
  /// rebuild olmaya devam eder, bu yüzden controller animasyon bitmeden
  /// dispose ediliyordu (zamanlamaya bağlı, bazen sıyırıp geçiyor bazen
  /// çöküyordu). Kalıcı çözüm: AYNI kod tabanında zaten kanıtlanmış deseni
  /// izleyen gerçek bir `StatefulWidget` (`_EmailChangeDialog`) — controller
  /// kendi `State.dispose()`'unda temizleniyor, ömrü Element'in gerçekten
  /// unmount olma anına bağlı.
  Future<void> _openEmailChangeDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _EmailChangeDialog(onSubmit: _submitEmailChange),
    );
  }

  Future<String?> _submitEmailChange(BuildContext dialogContext, String newEmail) async {
    try {
      await _client.rpc('request_email_change', params: {'p_new_email': newEmail});
      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Talebiniz gönderildi, admin onayı bekleniyor.')),
      );
      final userId = _client.auth.currentUser?.id;
      if (userId != null) _loadPendingEmailRequest(userId);
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    } catch (_) {
      return 'Talep gönderilemedi. Lütfen tekrar deneyin.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final ilceOptions = _selectedIl != null ? (turkiyeIlceleri[_selectedIl] ?? const []) : const <String>[];

    Widget body;
    if (_isLoadingProfile) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_loadError != null) {
      body = Center(child: Text(_loadError!));
    } else if (_role == 'personel') {
      // Faz 6 (2026-07-23): personelde ikinci bir "Değerlendirmelerim" alt
      // sekmesi eklendi — diğer roller (vatandaş/müdür/admin) puanlanmadığı
      // için sadece personelde iki sekmeli görünüme geçiliyor.
      body = DefaultTabController(
        length: 2,
        child: Column(
          children: [
            const TabBar(
              tabs: [Tab(text: 'Bilgilerim'), Tab(text: 'Değerlendirmelerim')],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildProfileFormTab(ilceOptions),
                  _PersonnelRatingsTab(personnelId: _client.auth.currentUser?.id),
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      body = _buildProfileFormTab(ilceOptions);
    }

    return NavigationShell(currentRoute: AppNavRoute.profile, title: 'Profilim', body: body);
  }

  Widget _buildProfileFormTab(List<String> ilceOptions) {
    return Center(
              child: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Stack(
                          children: [
                            UserAvatar(
                              avatarPath: _avatarPath,
                              fullName: _fullNameController.text,
                              radius: 44,
                              onTap: (_avatarPath == null || _avatarPath!.isEmpty)
                                  ? null
                                  : _showAvatarFullScreen,
                            ),
                            Positioned(
                              right: -4,
                              bottom: -4,
                              child: Material(
                                color: Theme.of(context).colorScheme.primary,
                                shape: const CircleBorder(),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: _isUploadingAvatar ? null : _pickAndUploadAvatar,
                                  child: Padding(
                                    padding: const EdgeInsets.all(6),
                                    child: _isUploadingAvatar
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_role == 'personel') ...[
                          const SizedBox(height: 8),
                          StarRatingDisplay(
                            rating: (_personnelRating?['avg_rating'] as num?)?.toDouble(),
                            ratingCount: _personnelRating?['rating_count'] as int?,
                          ),
                        ],
                        const SizedBox(height: 24),
                        Form(
                          key: _formKey,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextFormField(
                                initialValue: _email,
                                enabled: false,
                                decoration: const InputDecoration(labelText: 'E-posta'),
                              ),
                              if (_pendingEmailRequest != null) ...[
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Chip(
                                    visualDensity: VisualDensity.compact,
                                    avatar: const Icon(Icons.hourglass_top, size: 16),
                                    label: Text(
                                      '${_pendingEmailRequest!['requested_email']} — '
                                      '${_emailRequestStatusLabels[_pendingEmailRequest!['status']] ?? _pendingEmailRequest!['status']}',
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: _pendingEmailRequest != null ? null : _openEmailChangeDialog,
                                  icon: const Icon(Icons.email_outlined, size: 18),
                                  label: const Text('E-postamı Değiştir'),
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                initialValue: _roleLabel,
                                enabled: false,
                                decoration: InputDecoration(
                                  labelText: 'Rol',
                                  prefixIcon: Icon(roleIcon(_role)),
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                initialValue: _departmentLabel,
                                enabled: false,
                                decoration: const InputDecoration(labelText: 'Birim'),
                              ),
                              const SizedBox(height: 24),
                              TextFormField(
                                controller: _fullNameController,
                                decoration: const InputDecoration(labelText: 'Ad Soyad'),
                                validator: (value) => (value == null || value.trim().isEmpty)
                                    ? 'Ad soyad girin'
                                    : null,
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _phoneController,
                                keyboardType: TextInputType.phone,
                                inputFormatters: [PhoneInputFormatter()],
                                decoration: const InputDecoration(
                                  labelText: 'Telefon',
                                  hintText: '+90 (5XX) XXX XX XX',
                                ),
                                validator: Validators.phone,
                              ),
                              const SizedBox(height: 16),
                              DropdownButtonFormField<String>(
                                initialValue: _selectedIl,
                                decoration: const InputDecoration(labelText: 'İl'),
                                items: [
                                  for (final il in turkiyeIlleri)
                                    DropdownMenuItem(value: il, child: Text(il)),
                                ],
                                onChanged: (value) => setState(() {
                                  _selectedIl = value;
                                  // Yeni ilin ilçe listesinde geçerli olmayan
                                  // eski seçim temizlenir — aksi halde form,
                                  // dropdown'un items listesinde bulunmayan
                                  // bir değer taşıyıp assertion hatası verir.
                                  _selectedIlce = null;
                                }),
                                validator: (value) => value == null ? 'İl seçin' : null,
                              ),
                              const SizedBox(height: 16),
                              DropdownButtonFormField<String>(
                                key: ValueKey(_selectedIl),
                                initialValue: _selectedIlce,
                                decoration: const InputDecoration(labelText: 'İlçe'),
                                items: [
                                  for (final ilce in ilceOptions)
                                    DropdownMenuItem(value: ilce, child: Text(ilce)),
                                ],
                                onChanged: _selectedIl == null
                                    ? null
                                    : (value) => setState(() => _selectedIlce = value),
                                validator: (value) => value == null ? 'İlçe seçin' : null,
                              ),
                              const SizedBox(height: 24),
                              FilledButton(
                                onPressed: _isSaving ? null : _save,
                                child: _isSaving
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Text('Kaydet'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
  }
}

/// Faz 6 (2026-07-23) — personelin kendi aldığı puanları/yorumları listelediği
/// "Değerlendirmelerim" alt sekmesi. `request_ratings` tablosundan doğrudan
/// okuyor (RLS'in `puan_gorebilenler` politikası `personnel_id = auth.uid()`
/// satırlarını zaten izin veriyor, ayrı bir RPC gerekmiyor); talep başlığını
/// göstermek için `requests(title)` embed join'i kullanılıyor.
class _PersonnelRatingsTab extends StatefulWidget {
  const _PersonnelRatingsTab({required this.personnelId});

  final String? personnelId;

  @override
  State<_PersonnelRatingsTab> createState() => _PersonnelRatingsTabState();
}

class _PersonnelRatingsTabState extends State<_PersonnelRatingsTab>
    with AutomaticKeepAliveClientMixin {
  static SupabaseClient get _client => SupabaseService.client;

  List<Map<String, dynamic>> _ratings = [];
  bool _isLoading = true;
  String? _errorText;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadRatings();
  }

  Future<void> _loadRatings() async {
    final personnelId = widget.personnelId;
    if (personnelId == null) {
      setState(() {
        _isLoading = false;
        _errorText = 'Oturum bulunamadı.';
      });
      return;
    }

    try {
      final rows = await _client
          .from('request_ratings')
          .select('rating, comment, created_at, requests(title)')
          .eq('personnel_id', personnelId)
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() => _ratings = List<Map<String, dynamic>>.from(rows));
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorText = 'Değerlendirmeler yüklenemedi. Lütfen tekrar deneyin.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_errorText != null) return Center(child: Text(_errorText!));
    if (_ratings.isEmpty) {
      return const Center(child: Text('Henüz bir değerlendirme almadınız.'));
    }

    return RefreshIndicator(
      onRefresh: _loadRatings,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _ratings.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final row = _ratings[index];
          final request = row['requests'] as Map<String, dynamic>?;
          final comment = row['comment'] as String?;

          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          request?['title'] as String? ?? 'Talep',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      StarRatingDisplay(
                        rating: (row['rating'] as int).toDouble(),
                        showCount: false,
                        size: 16,
                      ),
                    ],
                  ),
                  if (comment != null && comment.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(comment, style: const TextStyle(fontStyle: FontStyle.italic)),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// "E-postamı Değiştir" ile açılan dialog. `admin_department_screen.dart`
/// içindeki `_EditDepartmentDialog` ile AYNI deseni izler: kendi
/// `TextEditingController`'ını kendi `State.dispose()`'unda temizler (bkz.
/// `_ProfileScreenState._openEmailChangeDialog` üzerindeki kök neden
/// açıklaması) — `onSubmit`, başarıda `null`, hatada gösterilecek Türkçe
/// mesajı döndürür; başarı durumunda dialogu kapatmak `onSubmit`'in kendi
/// sorumluluğundadır (bkz. `_submitEmailChange`).
class _EmailChangeDialog extends StatefulWidget {
  final Future<String?> Function(BuildContext dialogContext, String newEmail) onSubmit;

  const _EmailChangeDialog({required this.onSubmit});

  @override
  State<_EmailChangeDialog> createState() => _EmailChangeDialogState();
}

class _EmailChangeDialogState extends State<_EmailChangeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorText;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _errorText = null;
      _isSubmitting = true;
    });
    final error = await widget.onSubmit(context, _emailController.text.trim());
    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _errorText = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('E-postamı Değiştir'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Yeni e-posta adresiniz, admin onayladıktan sonra aktif olur.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailController,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: 'Yeni E-posta', errorText: _errorText),
              validator: (value) => (value == null || !value.contains('@'))
                  ? 'Geçerli bir e-posta adresi girin'
                  : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('İptal'),
        ),
        TextButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Talep Gönder'),
        ),
      ],
    );
  }
}

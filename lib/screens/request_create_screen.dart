import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';
import 'my_requests_screen.dart';

enum _MediaKind { image, video, document }

/// Kullanıcının seçtiği ama henüz Storage'a yüklenmemiş bir medya/belge
/// dosyası. [previewBytes] sadece fotoğraflar için doldurulur (önizleme
/// amaçlı); videolar ve belgeler şimdilik sadece ikon + dosya adıyla temsil
/// ediliyor. Fotoğraf/video için [xFile] (image_picker), belge için
/// [platformFile] (file_picker) dolu olur.
class _PickedMedia {
  const _PickedMedia({
    required this.kind,
    required this.fileName,
    this.previewBytes,
    this.xFile,
    this.platformFile,
  });

  final _MediaKind kind;
  final String fileName;
  final Uint8List? previewBytes;
  final XFile? xFile;
  final PlatformFile? platformFile;
}

/// Talep/şikâyet oluşturma ekranı. Hem anonim (hesapsız), hem hesaplı
/// vatandaş, hem de personel buradan talep açabilir. `requester_type` ve
/// `created_by` kullanıcıya hiç sorulmaz; oturum durumuna ve public.users'daki
/// role'e bakılarak otomatik belirlenir (bkz. CLAUDE.md — hibrit vatandaş
/// erişimi modeli). `id`, `created_at`, `status`, `assigned_to`,
/// `access_token` alanlarına dokunulmaz; hepsinin veritabanında otomatik
/// varsayılanı vardır.
class RequestCreateScreen extends StatefulWidget {
  const RequestCreateScreen({super.key});

  @override
  State<RequestCreateScreen> createState() => _RequestCreateScreenState();
}

class _RequestCreateScreenState extends State<RequestCreateScreen> {
  static SupabaseClient get _client => SupabaseService.client;

  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _categoryController = TextEditingController();

  List<Map<String, dynamic>> _departments = [];
  int? _selectedDepartmentId;
  bool _isLoadingDepartments = true;
  bool _isSubmitting = false;

  final ImagePicker _picker = ImagePicker();
  final List<_PickedMedia> _pickedMedia = [];

  @override
  void initState() {
    super.initState();
    _loadDepartments();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  Future<void> _loadDepartments() async {
    try {
      final response = await _client
          .from('departments')
          .select('id, name')
          .eq('is_active', true)
          .order('name');
      setState(() => _departments = List<Map<String, dynamic>>.from(response));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Birimler yüklenemedi. Lütfen sayfayı yenileyin.')),
      );
    } finally {
      if (mounted) setState(() => _isLoadingDepartments = false);
    }
  }

  /// Giriş yapılmamışsa 'anonim'; giriş yapılmışsa public.users'daki role'e
  /// göre 'vatandas' ya da 'personel' (personel/müdür/admin) döner.
  Future<String> _resolveRequesterType(String? currentUserId) async {
    if (currentUserId == null) return 'anonim';

    final profile = await _client
        .from('users')
        .select('role')
        .eq('id', currentUserId)
        .single();
    final role = profile['role'] as String;
    return role == 'vatandas' ? 'vatandas' : 'personel';
  }

  Future<void> _submit() async {
    // Peş peşe tıklamalara karşı koruma: _isSubmitting=true olduktan sonraki
    // tıklamalar, buton henüz (rebuild ile) devre dışı görünmese bile burada
    // hemen elenir. Dart tek iş parçacıklı olduğu için bu kontrol, ilk
    // "await"e kadar olan senkron kod bloğu tamamlanana kadar başka bir
    // _submit() çağrısının araya giremeyeceğini garanti eder.
    if (_isSubmitting) return;
    if (_selectedDepartmentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen bir birim seçin.')),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      final currentUserId = _client.auth.currentUser?.id;
      final requesterType = await _resolveRequesterType(currentUserId);

      final result = await _client.rpc('create_request', params: {
        'p_title': _titleController.text.trim(),
        'p_description': _descriptionController.text.trim(),
        'p_category': _categoryController.text.trim(),
        'p_department_id': _selectedDepartmentId,
        'p_requester_type': requesterType,
        'p_created_by': currentUserId,
      }) as Map<String, dynamic>;

      final requestId = result['id'] as String;
      final accessToken = result['access_token'] as String;

      final failedUploads = _pickedMedia.isEmpty
          ? const <String>[]
          : await _uploadPickedMedia(requestId);

      if (!mounted) return;

      if (requesterType == 'anonim') {
        // Anonim kullanıcı için erişim kodu talebi tekrar bulabilmesinin tek
        // yolu — dialog kullanıcı kapatana kadar ekranda kalmalı, otomatik
        // yönlendirme yapılmaz.
        if (failedUploads.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Talep oluşturuldu ama şu dosyalar yüklenemedi: ${failedUploads.join(', ')}',
              ),
            ),
          );
        }
        _showAccessTokenDialog(accessToken, requesterType);
        return;
      }

      // Giriş yapmış kullanıcılar (vatandaş/personel) erişim koduna muhtaç
      // değil — hesaplarından "Taleplerim" ekranıyla her zaman ulaşabilirler.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failedUploads.isEmpty
                ? 'Talebiniz başarıyla oluşturuldu.'
                : 'Talebiniz oluşturuldu ama şu dosyalar yüklenemedi: ${failedUploads.join(', ')}',
          ),
        ),
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MyRequestsScreen()),
      );
    } on PostgrestException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Talep oluşturulamadı. Lütfen tekrar deneyin.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin.')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Seçilen her medyayı sırayla `request-attachments` bucket'ına
  /// `{requestId}/{benzersiz_ad}` yoluna yükler ve `attachments` tablosuna
  /// bir satır ekler. Talep zaten oluşturulmuş olduğu için bir dosya
  /// başarısız olsa bile diğerlerine devam edilir; başarısız olan dosya
  /// adları döndürülür (hiçbiri başarısız olmazsa boş liste).
  Future<List<String>> _uploadPickedMedia(String requestId) async {
    final failedFileNames = <String>[];

    for (final media in _pickedMedia) {
      try {
        final bytes = media.kind == _MediaKind.document
            ? media.platformFile!.bytes!
            : await media.xFile!.readAsBytes();
        final mimeType = _guessMimeType(media.fileName, media.kind);
        final uniqueName = '${DateTime.now().microsecondsSinceEpoch}_${media.fileName}';
        final storagePath = '$requestId/$uniqueName';

        await _client.storage
            .from('request-attachments')
            .uploadBinary(storagePath, bytes, fileOptions: FileOptions(contentType: mimeType));

        await _client.from('attachments').insert({
          'request_id': requestId,
          'file_url': storagePath,
          'media_type': media.kind.name,
        });
      } catch (_) {
        failedFileNames.add(media.fileName);
      }
    }

    return failedFileNames;
  }

  /// `request-attachments` bucket'ının `allowed_mime_types` listesiyle
  /// birebir eşleşen, dosya uzantısına göre basit bir MIME type tahmini.
  String _guessMimeType(String fileName, _MediaKind kind) {
    switch (fileName.toLowerCase().split('.').last) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'pdf':
        return 'application/pdf';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      default:
        return switch (kind) {
          _MediaKind.image => 'image/jpeg',
          _MediaKind.video => 'video/mp4',
          _MediaKind.document => 'application/pdf',
        };
    }
  }

  Future<void> _pickMedia(_MediaKind kind, ImageSource source) async {
    final XFile? file = kind == _MediaKind.image
        ? await _picker.pickImage(source: source, imageQuality: 85)
        : await _picker.pickVideo(source: source);
    if (file == null) return;

    final previewBytes = kind == _MediaKind.image ? await file.readAsBytes() : null;
    if (!mounted) return;
    setState(() {
      _pickedMedia.add(
        _PickedMedia(kind: kind, fileName: file.name, previewBytes: previewBytes, xFile: file),
      );
    });
  }

  Future<void> _pickDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx'],
      withData: true,
    );
    final picked = result?.files.first;
    if (picked == null) return;

    if (!mounted) return;
    setState(() {
      _pickedMedia.add(
        _PickedMedia(kind: _MediaKind.document, fileName: picked.name, platformFile: picked),
      );
    });
  }

  void _removeMedia(int index) {
    setState(() => _pickedMedia.removeAt(index));
  }

  Future<void> _showMediaMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Galeriden Fotoğraf'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pickMedia(_MediaKind.image, ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Kameradan Fotoğraf'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pickMedia(_MediaKind.image, ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.video_library),
              title: const Text('Galeriden Video'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pickMedia(_MediaKind.video, ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('Kameradan Video'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pickMedia(_MediaKind.video, ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file),
              title: const Text('Belge Seç (PDF/DOCX)'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pickDocument();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAccessTokenDialog(String accessToken, String requesterType) {
    final description = requesterType == 'anonim'
        ? 'Bu kodu saklayın — talebinizin durumunu ileride bu kodla, hesap açmadan sorgulayabilirsiniz.'
        : 'Talebiniz oluşturuldu. Bu kod, talebinizin referans numarasıdır.';

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Talep Oluşturuldu'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(description),
            const SizedBox(height: 16),
            SelectableText(
              accessToken,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 2),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: accessToken));
              if (!dialogContext.mounted) return;
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                const SnackBar(content: Text('Kod kopyalandı.')),
              );
            },
            icon: const Icon(Icons.copy),
            label: const Text('Kopyala'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Talep Oluştur')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(labelText: 'Başlık'),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty) ? 'Başlık girin' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descriptionController,
                    maxLines: 5,
                    decoration: const InputDecoration(labelText: 'Açıklama'),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty) ? 'Açıklama girin' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _categoryController,
                    decoration: const InputDecoration(labelText: 'Kategori'),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty) ? 'Kategori girin' : null,
                  ),
                  const SizedBox(height: 16),
                  _isLoadingDepartments
                      ? const Center(child: CircularProgressIndicator())
                      : DropdownButtonFormField<int>(
                          initialValue: _selectedDepartmentId,
                          decoration: const InputDecoration(labelText: 'Birim'),
                          items: _departments
                              .map(
                                (department) => DropdownMenuItem<int>(
                                  value: department['id'] as int,
                                  child: Text(department['name'] as String),
                                ),
                              )
                              .toList(),
                          onChanged: (value) => setState(() => _selectedDepartmentId = value),
                        ),
                  const SizedBox(height: 16),
                  if (_pickedMedia.isNotEmpty) ...[
                    SizedBox(
                      height: 90,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _pickedMedia.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final media = _pickedMedia[index];
                          return Stack(
                            children: [
                              Container(
                                width: 90,
                                height: 90,
                                clipBehavior: Clip.antiAlias,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                ),
                                child: media.previewBytes != null
                                    ? Image.memory(media.previewBytes!, fit: BoxFit.cover)
                                    : media.kind == _MediaKind.document
                                        ? Padding(
                                            padding: const EdgeInsets.all(4),
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                const Icon(Icons.insert_drive_file, size: 28),
                                                const SizedBox(height: 2),
                                                Text(
                                                  media.fileName,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: Theme.of(context).textTheme.labelSmall,
                                                ),
                                              ],
                                            ),
                                          )
                                        : const Icon(Icons.videocam, size: 36),
                              ),
                              Positioned(
                                top: 2,
                                right: 2,
                                child: GestureDetector(
                                  onTap: () => _removeMedia(index),
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.close, size: 16, color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  OutlinedButton.icon(
                    onPressed: _showMediaMenu,
                    icon: const Icon(Icons.attach_file),
                    label: const Text('Medya Ekle'),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _isSubmitting ? null : _submit,
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Gönder'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

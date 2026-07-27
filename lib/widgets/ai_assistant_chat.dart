import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/ai_assistant_service.dart';
import '../services/supabase_service.dart';
import 'ai_analysis_result_view.dart';

class _ChatEntry {
  _ChatEntry.user(String text, {this.imageBytes})
      : userText = text,
        result = null,
        errorMessage = null,
        isUser = true;

  _ChatEntry.model(this.result)
      : userText = null,
        imageBytes = null,
        errorMessage = null,
        isUser = false;

  _ChatEntry.error(String message)
      : userText = null,
        imageBytes = null,
        result = null,
        errorMessage = message,
        isUser = false;

  final bool isUser;
  final String? userText;
  final Uint8List? imageBytes;
  final AiAnalysisResult? result;
  final String? errorMessage;
}

/// Arıza Talep Asistanı'nın sohbet tarzı gövdesi (2026-07-27) — hem Ana
/// ekrandaki rozet ikonundan açılan `BottomSheet`'te, hem sidebar'daki
/// bağımsız `AiAssistantScreen`'de, hem `RequestCreateScreen` içine gömülü
/// panelde AYNI widget kullanılıyor. Kullanıcı mesaj yazıp devam edebiliyor
/// (ör. "denedim ama olmadı") — her turda TÜM sohbet geçmişi Gemini'ye
/// gönderiliyor, böylece bir önceki turda önerilenler tekrar edilmiyor.
///
/// Asistan yine de genel bir sohbet botu DEĞİL: her yanıt, backend'deki katı
/// `responseSchema` yüzünden hep aynı üç alanlı (quick_fixes, department_name,
/// department_reason) yapıya uymak zorunda; bu widget o yapıyı [AiAnalysisResultView]
/// ile bir "asistan balonu" içinde gösteriyor.
class AiAssistantChat extends StatefulWidget {
  const AiAssistantChat({
    super.key,
    this.initialUserMessage,
    this.onDepartmentAction,
    this.departmentActionLabel = 'Bu Birimle Talep Oluştur',
  });

  /// Verilirse, sohbet açılır açılmaz otomatik olarak ilk kullanıcı mesajı
  /// gibi gönderilir (ör. talep formundaki Açıklama alanının o anki metni).
  final String? initialUserMessage;

  /// Asistan bir birim önerdiğinde VE bu birim sistemdeki gerçek bir birimle
  /// eşleştiğinde gösterilecek aksiyon butonuna basıldığında çağrılır.
  /// `null` ise buton hiç gösterilmez.
  final void Function(int departmentId, String lastUserText)? onDepartmentAction;
  final String departmentActionLabel;

  @override
  State<AiAssistantChat> createState() => _AiAssistantChatState();
}

class _AiAssistantChatState extends State<AiAssistantChat> with WidgetsBindingObserver {
  static SupabaseClient get _client => SupabaseService.client;

  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  final List<_ChatEntry> _entries = [];
  final List<ChatTurn> _history = [];
  List<Map<String, dynamic>> _departments = [];
  bool _isSending = false;
  String _lastUserText = '';
  double _lastBottomInset = 0;
  Uint8List? _pendingImageBytes;
  String? _pendingImageMime;
  final _imagePicker = ImagePicker();
  static const _maxAiImageBytes = 1 * 1024 * 1024;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _focusNode.addListener(_onFocusChanged);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focusNode.removeListener(_onFocusChanged);
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Klavye açılınca (viewInsets.bottom artınca) sohbeti alta kaydır —
  /// yazı alanı ve son mesajlar görünür kalsın.
  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    final bottom = WidgetsBinding.instance.platformDispatcher.views.isEmpty
        ? 0.0
        : WidgetsBinding.instance.platformDispatcher.views.first.viewInsets.bottom /
            WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
    if (bottom > _lastBottomInset + 1) {
      _scrollToBottom();
    }
    _lastBottomInset = bottom;
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      _scrollToBottom();
    }
  }

  Future<void> _init() async {
    await _loadDepartments();
    final initial = widget.initialUserMessage?.trim();
    if (initial != null && initial.length >= 5) {
      _send(initial);
    }
  }

  Future<void> _loadDepartments() async {
    try {
      final response = await _client
          .from('departments')
          .select('id, name')
          .eq('is_active', true)
          .order('name');
      if (mounted) setState(() => _departments = List<Map<String, dynamic>>.from(response));
    } catch (_) {
      // Sessizce yutulur — birim listesi boş kalırsa asistan yine de çalışır,
      // sadece department_name eşleştirmesi (ve aksiyon butonu) devreye
      // girmez.
    }
  }

  int? _matchDepartmentId(String? departmentName) {
    if (departmentName == null) return null;
    for (final department in _departments) {
      if ((department['name'] as String).trim().toLowerCase() == departmentName.trim().toLowerCase()) {
        return department['id'] as int;
      }
    }
    return null;
  }

  Future<void> _pickImage() async {
    final file = await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 75);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.length > _maxAiImageBytes) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fotoğraf en fazla 1 MB olabilir.')),
      );
      return;
    }
    final lower = file.name.toLowerCase();
    final mime = lower.endsWith('.png')
        ? 'image/png'
        : lower.endsWith('.webp')
            ? 'image/webp'
            : 'image/jpeg';
    if (!mounted) return;
    setState(() {
      _pendingImageBytes = bytes;
      _pendingImageMime = mime;
    });
  }

  Future<void> _send([String? textOverride]) async {
    final text = (textOverride ?? _textController.text).trim();
    final imageBytes = _pendingImageBytes;
    final imageMime = _pendingImageMime;
    if ((text.length < 2 && imageBytes == null) || _isSending) return;

    final displayText = text.isEmpty ? '(Fotoğraf eklendi)' : text;
    setState(() {
      _entries.add(_ChatEntry.user(displayText, imageBytes: imageBytes));
      _history.add(ChatTurn.user(
        text.isEmpty ? 'Eklediğim fotoğraftaki arızayı/sorunu incele.' : text,
        imageBase64: imageBytes == null ? null : base64Encode(imageBytes),
        imageMimeType: imageMime,
      ));
      _lastUserText = text.isEmpty ? displayText : text;
      _isSending = true;
      _textController.clear();
      _pendingImageBytes = null;
      _pendingImageMime = null;
    });
    _scrollToBottom();

    try {
      final result = await AiAssistantService.sendMessage(
        history: _history,
        departmentNames: _departments.map((d) => d['name'] as String).toList(),
      );
      _history.add(ChatTurn.model(result.toRawText()));
      if (mounted) setState(() => _entries.add(_ChatEntry.model(result)));
    } on AiAssistantException catch (e) {
      if (mounted) setState(() => _entries.add(_ChatEntry.error(e.message)));
    } catch (_) {
      if (mounted) {
        setState(() => _entries.add(_ChatEntry.error('Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin.')));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Widget _buildUserBubble(BuildContext context, String text, {Uint8List? imageBytes}) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (imageBytes != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(imageBytes, height: 120, fit: BoxFit.cover),
              ),
              const SizedBox(height: 6),
            ],
            Text(text, style: TextStyle(color: theme.colorScheme.onPrimary)),
          ],
        ),
      ),
    );
  }

  Widget _buildModelBubble(BuildContext context, AiAnalysisResult result) {
    final theme = Theme.of(context);
    final matchedId = _matchDepartmentId(result.departmentName);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.88),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: AiAnalysisResultView(
          result: result,
          matchedDepartmentId: matchedId,
          createRequestLabel: widget.departmentActionLabel,
          onCreateRequest: (matchedId != null && widget.onDepartmentAction != null)
              ? () => widget.onDepartmentAction!(matchedId, _lastUserText)
              : null,
        ),
      ),
    );
  }

  Widget _buildErrorBubble(BuildContext context, String message) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(message, style: const TextStyle(color: Colors.red)),
      ),
    );
  }

  Widget _buildTypingIndicator(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 10),
            Text('Asistan yazıyor...'),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.smart_toy_outlined, size: 40, color: onSurface.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text(
              'Sorununuzu yazın, size hızlı çözümler önerelim.',
              textAlign: TextAlign.center,
              style: TextStyle(color: onSurface.withValues(alpha: 0.6)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(BuildContext context) {
    // Sistem navigasyon / jest çubuğunun üstünde kalsın; klavye açıksa
    // SafeArea alt padding genelde 0 olur (klavye viewInsets'e geçer).
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_pendingImageBytes != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(_pendingImageBytes!, height: 56, width: 56, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Fotoğraf eklendi (max 1 MB)')),
                  IconButton(
                    tooltip: 'Kaldır',
                    onPressed: () => setState(() {
                      _pendingImageBytes = null;
                      _pendingImageMime = null;
                    }),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Fotoğraf ekle',
                  onPressed: _isSending ? null : _pickImage,
                  icon: const Icon(Icons.image_outlined),
                ),
                Expanded(
                  child: TextField(
                    controller: _textController,
                    focusNode: _focusNode,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    onTap: _scrollToBottom,
                    scrollPadding: const EdgeInsets.only(bottom: 100),
                    decoration: const InputDecoration(
                      hintText: 'Sorununuzu yazın...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(24))),
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _isSending ? null : () => _send(),
                  icon: _isSending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _entries.isEmpty
              ? _buildEmptyState(context)
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  itemCount: _entries.length + (_isSending ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= _entries.length) return _buildTypingIndicator(context);
                    final entry = _entries[index];
                    if (entry.isUser) {
                      return _buildUserBubble(
                        context,
                        entry.userText!,
                        imageBytes: entry.imageBytes,
                      );
                    }
                    if (entry.errorMessage != null) return _buildErrorBubble(context, entry.errorMessage!);
                    return _buildModelBubble(context, entry.result!);
                  },
                ),
        ),
        const Divider(height: 1),
        _buildInputBar(context),
      ],
    );
  }
}

/// [AiAssistantChat]'i bir `BottomSheet` içinde açan paylaşılan yardımcı
/// fonksiyon — Ana ekrandaki rozet ikonu ve `RequestCreateScreen`'deki
/// gömülü panel AYNI görsel dili kullanır.
///
/// Klavye / alt sistem paneli (2026-07-27): Sheet yüksekliği klavye açılınca
/// kalan alana göre yeniden hesaplanır ve `viewInsets.bottom` kadar yukarı
/// kaydırılır; böylece yazı alanı telefonun alt paneli/klavye altında kalmaz.
Future<void> showAiAssistantChatSheet(
  BuildContext context, {
  String? initialUserMessage,
  void Function(int departmentId, String lastUserText)? onDepartmentAction,
  String departmentActionLabel = 'Bu Birimle Talep Oluştur',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      final media = MediaQuery.of(sheetContext);
      final keyboard = media.viewInsets.bottom;
      // Klavye üstünde kalan alanın büyük kısmını sheet kaplar (önceden
      // sabit %75 + yanlış padding yüzünden yazı alanı altta kalıyordu).
      final available = (media.size.height - keyboard).clamp(280.0, media.size.height);
      final sheetHeight = available * 0.95;

      return AnimatedPadding(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: keyboard),
        child: SizedBox(
          height: sheetHeight,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
                child: Row(
                  children: [
                    const Icon(Icons.smart_toy_outlined, color: Colors.deepOrange),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Arıza Asistanı',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(sheetContext).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: AiAssistantChat(
                  initialUserMessage: initialUserMessage,
                  departmentActionLabel: departmentActionLabel,
                  onDepartmentAction: onDepartmentAction == null
                      ? null
                      : (departmentId, lastUserText) {
                          Navigator.of(sheetContext).pop();
                          onDepartmentAction(departmentId, lastUserText);
                        },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

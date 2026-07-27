import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// `analyze-request` Supabase Edge Function'ının döndürdüğü yapılandırılmış
/// analiz sonucu (bkz. `supabase/functions/analyze-request/index.ts`'teki
/// `responseSchema`).
class AiAnalysisResult {
  const AiAnalysisResult({
    required this.quickFixes,
    required this.departmentReason,
    this.departmentName,
  });

  factory AiAnalysisResult.fromJson(Map<String, dynamic> json) {
    return AiAnalysisResult(
      quickFixes: (json['quick_fixes'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .where((e) => e.trim().isNotEmpty)
              .toList() ??
          const [],
      departmentName: (json['department_name'] as String?)?.trim().isEmpty ?? true
          ? null
          : (json['department_name'] as String).trim(),
      departmentReason: json['department_reason'] as String? ?? '',
    );
  }

  final List<String> quickFixes;
  final String? departmentName;
  final String departmentReason;

  /// Arıza dışı / alakasız bir mesajda model çözüm önermez ve birim
  /// önermez — UI bu durumda kullanıcıya "lütfen arıza bildirisi girin"
  /// uyarısını gösterir.
  bool get isOffTopic => quickFixes.isEmpty && departmentName == null;

  /// Bu sonucu, sohbet geçmişinde bir "model" turu olarak Gemini'ye geri
  /// göndermek için ham JSON metnine çevirir (bkz. `ChatTurn.model`) — modelin
  /// önceki turda tam olarak ne söylediğini hatırlamasını sağlar.
  String toRawText() {
    final fixes = quickFixes.map((f) => '"${f.replaceAll('"', "'")}"').join(',');
    final dept = departmentName == null ? 'null' : '"${departmentName!.replaceAll('"', "'")}"';
    final reason = departmentReason.replaceAll('"', "'");
    return '{"quick_fixes":[$fixes],"department_name":$dept,"department_reason":"$reason"}';
  }
}

/// Sohbet geçmişindeki tek bir tur — kullanıcı mesajı ya da asistanın
/// (yapılandırılmış) yanıtı. Kullanıcı turunda opsiyonel bir görsel
/// (base64 + mime) taşınabilir.
class ChatTurn {
  const ChatTurn.user(
    this.text, {
    this.imageBase64,
    this.imageMimeType,
  }) : role = 'user';

  const ChatTurn.model(this.text)
      : role = 'model',
        imageBase64 = null,
        imageMimeType = null;

  final String role;
  final String text;
  final String? imageBase64;
  final String? imageMimeType;

  Map<String, dynamic> toJson() => {
        'role': role,
        'text': text,
        if (imageBase64 != null) 'image_base64': imageBase64,
        if (imageMimeType != null) 'image_mime_type': imageMimeType,
      };
}

/// Arıza Talep Asistanı — kullanıcının yazdığı sorun metnini Gemini API ile
/// analiz ettiren `analyze-request` Edge Function'ını çağırır. Çok turlu
/// sohbeti desteklemek için her çağrıda TÜM geçmiş (bu ana kadarki mesajlar)
/// gönderilir; Gemini bir önceki turda ne söylediğini hatırlayıp aynı
/// önerileri tekrarlamaz.
///
/// GÜVENLİK: Gemini API anahtarı bu istemci kodunda HİÇ bulunmaz; anahtar
/// sadece Edge Function'ın sunucu tarafı bir Supabase secret'ı olarak
/// saklanır. Bu servis sadece "bu sohbeti analiz et" isteği gönderir.
class AiAssistantService {
  static SupabaseClient get _client => SupabaseService.client;

  static Future<AiAnalysisResult> sendMessage({
    required List<ChatTurn> history,
    required List<String> departmentNames,
  }) async {
    final response = await _client.functions.invoke(
      'analyze-request',
      body: {
        'messages': history.map((t) => t.toJson()).toList(),
        'departments': departmentNames,
      },
    );

    final data = response.data;
    if (response.status != 200 || data is! Map) {
      final errorMessage = (data is Map ? data['error'] as String? : null) ??
          'Asistan şu anda yanıt veremiyor. Lütfen daha sonra tekrar deneyin.';
      throw AiAssistantException(errorMessage);
    }

    return AiAnalysisResult.fromJson(Map<String, dynamic>.from(data));
  }
}

class AiAssistantException implements Exception {
  AiAssistantException(this.message);
  final String message;

  @override
  String toString() => message;
}

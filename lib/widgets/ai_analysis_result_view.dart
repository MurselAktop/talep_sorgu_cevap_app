import 'package:flutter/material.dart';

import '../services/ai_assistant_service.dart';
import '../theme/app_theme.dart';

/// Arıza Talep Asistanı'nın analiz sonucunu gösteren paylaşılan görünüm.
/// Hem bağımsız `AiAssistantScreen`'de hem `RequestCreateScreen` içine
/// gömülen alt sayfada (bottom sheet) AYNI görsel dille kullanılıyor.
class AiAnalysisResultView extends StatelessWidget {
  const AiAnalysisResultView({
    super.key,
    required this.result,
    this.matchedDepartmentId,
    this.onCreateRequest,
    this.createRequestLabel = 'Bu Birimle Talep Oluştur',
  });

  final AiAnalysisResult result;

  /// Gemini'nin önerdiği `department_name`, sistemdeki gerçek birim
  /// listesiyle eşleştiyse bu birimin `id`'si; eşleşmediyse null.
  final int? matchedDepartmentId;

  /// Kullanıcı "talep oluştur" aksiyonuna bastığında çağrılır. `null` ise
  /// (eşleşen birim yoksa) buton hiç gösterilmez.
  final VoidCallback? onCreateRequest;
  final String createRequestLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.lightbulb_outline, color: AppTheme.aiAccent),
            const SizedBox(width: 8),
            Text(
              'Deneyebileceğiniz Çözümler',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (result.isOffTopic)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.aiAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.aiAccent.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.info_outline, color: AppTheme.aiAccent, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Hazır bir çözüm bulunamadı',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  result.departmentReason.trim().isNotEmpty
                      ? result.departmentReason.trim()
                      : 'Bu bir arıza bildirisi değil. Lütfen yaşadığınız arıza veya sorunu yazınız.',
                  style: TextStyle(color: onSurface.withValues(alpha: 0.85)),
                ),
                const SizedBox(height: 6),
                Text(
                  'Örnek: "Bilgisayarım internete bağlanmıyor", "Yazıcı çalışmıyor".',
                  style: TextStyle(
                    fontSize: 12,
                    color: onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          )
        else if (result.quickFixes.isEmpty)
          Text(
            'Bu sorun için hazır bir öneri bulunamadı.',
            style: TextStyle(color: onSurface.withValues(alpha: 0.6)),
          )
        else
          ...result.quickFixes.asMap().entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 11,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Text(
                          '${entry.key + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(entry.value)),
                    ],
                  ),
                ),
              ),
        if (!result.isOffTopic) ...[
          const SizedBox(height: 16),
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.apartment, color: theme.colorScheme.primary, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          result.departmentName != null
                              ? 'Çözülmezse: ${result.departmentName}'
                              : 'Şimdilik bir birime yönlendirme gerekmiyor',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  if (result.departmentReason.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      result.departmentReason,
                      style: TextStyle(fontSize: 13, color: onSurface.withValues(alpha: 0.75)),
                    ),
                  ],
                  if (result.departmentName != null &&
                      matchedDepartmentId != null &&
                      onCreateRequest != null) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: onCreateRequest,
                        icon: const Icon(Icons.add_circle_outline),
                        label: Text(createRequestLabel),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

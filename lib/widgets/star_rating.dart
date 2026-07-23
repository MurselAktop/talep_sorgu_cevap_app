import 'package:flutter/material.dart';

/// Personel ortalama puanını (Trendyol tarzı "4.5 (12)") salt-okunur olarak
/// gösteren paylaşılan widget — talep detayında, müdürün "Ata" ekranında,
/// admin'in Kullanıcı Yönetimi'nde, profil ekranında ve istatistik
/// dashboard'unda AYNI görsel dilde kullanılır (2026-07-23 puanlama isteği).
class StarRatingDisplay extends StatelessWidget {
  const StarRatingDisplay({
    super.key,
    required this.rating,
    this.ratingCount,
    this.size = 16,
    this.showCount = true,
    this.emptyLabel = 'Henüz puan yok',
  });

  final double? rating;
  final int? ratingCount;
  final double size;
  final bool showCount;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    if (rating == null || (ratingCount ?? 1) == 0) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_border, size: size, color: Colors.grey),
          SizedBox(width: size * 0.3),
          Text(emptyLabel, style: TextStyle(fontSize: size * 0.8, color: Colors.grey)),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star, size: size, color: Colors.amber),
        SizedBox(width: size * 0.3),
        Text(
          rating!.toStringAsFixed(1),
          style: TextStyle(fontSize: size * 0.9, fontWeight: FontWeight.bold),
        ),
        if (showCount && ratingCount != null) ...[
          SizedBox(width: size * 0.3),
          Text(
            '($ratingCount)',
            style: TextStyle(fontSize: size * 0.75, color: Colors.grey.shade600),
          ),
        ],
      ],
    );
  }
}

/// Talebi puanlama dialogunda kullanılan, tıklanabilir 1-5 yıldız girişi.
class StarRatingInput extends StatelessWidget {
  const StarRatingInput({super.key, required this.rating, required this.onChanged, this.size = 36});

  final int rating;
  final ValueChanged<int> onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    // IconButton'un varsayılan iç dolgusu (8dp her yönde), 5 yıldız yan yana
    // dar ekranlarda (dialog içeriği ~256dp) birkaç piksellik bir sağa taşmaya
    // (RenderFlex overflow) yol açıyordu — dar bir `padding` ile bu kesin
    // olarak engelleniyor, `visualDensity` tek başına padding'i sıfırlamıyor.
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 1; i <= 5; i++)
          IconButton(
            iconSize: size,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            constraints: const BoxConstraints(),
            icon: Icon(i <= rating ? Icons.star : Icons.star_border, color: Colors.amber),
            onPressed: () => onChanged(i),
          ),
      ],
    );
  }
}

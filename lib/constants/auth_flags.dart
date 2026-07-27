/// Geçici kimlik doğrulama bayrakları.
///
/// Fake / test e-postalar Cloud SMTP ile doğrulanamadığı için (2026-07-27)
/// e-posta doğrulaması şimdilik kapalı. Gerçek SMTP bağlanınca
/// [emailVerificationEnabled] tekrar `true` yapılmalı.
const bool emailVerificationEnabled = false;

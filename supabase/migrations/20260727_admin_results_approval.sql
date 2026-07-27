-- Admin'in results onay/red güncellemesi (2026-07-27)
--
-- web panel, admin'e Onayla/Reddet butonlarını gösteriyordu ama
-- `mudur_onay_verebilir` politikası yalnızca role='mudur' izin veriyordu.
-- PostgREST, RLS yüzünden 0 satır güncellenince hata DÖNDÜRMEZ — bu yüzden
-- buton "çalışmıyor" gibi görünüyordu. Admin'in sistem genelinde müdahale
-- yetkisi (CLAUDE.md) results onayına da uygulanır.

CREATE POLICY "admin_onay_verebilir"
  ON "public"."results"
  FOR UPDATE
  TO "authenticated"
  USING (public.current_user_role() = 'admin')
  WITH CHECK (public.current_user_role() = 'admin');

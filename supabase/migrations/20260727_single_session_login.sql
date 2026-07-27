--
-- Tek cihaz/oturum sınırlaması (2026-07-27). Bir hesap aynı anda sadece TEK
-- bir cihazda/oturumda aktif sayılır. Her GERÇEK giriş anında (şifre girişi,
-- giriş OTP'si, kayıt e-posta doğrulaması, şifre sıfırlama sonrası) Flutter
-- tarafı `register_active_session()`'ı çağırıp dönen yeni token'ı yerelde
-- saklıyor; bu, varsa aynı hesabın BAŞKA bir cihazdaki eski token'ını
-- otomatik geçersiz kılıyor (aynı satır güncellendiği için — ayrı bir
-- "sessions" tablosu yerine BİLİNÇLİ olarak `users` üzerinde tek bir sütun
-- kullanıldı, çünkü kural gereği bir hesabın aynı anda sadece TEK bir aktif
-- oturumu olabiliyor, geçmiş oturumların ayrıca listelenmesi gerekmiyor).
-- `NavigationShell` (uygulama içi periyodik kontrol) ve `WelcomeBackScreen`
-- (uygulama açılışında sessiz devam) daha sonra `check_active_session()`'ı
-- çağırıp yereldeki token hâlâ sunucudakiyle eşleşiyor mu diye bakıyor;
-- eşleşmiyorsa hesap başka bir cihazda yeniden giriş yapmış demektir.
--

ALTER TABLE "public"."users" ADD COLUMN IF NOT EXISTS "active_session_token" "uuid";


CREATE OR REPLACE FUNCTION "public"."register_active_session"() RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_token uuid := gen_random_uuid();
begin
  if auth.uid() is null then
    raise exception 'Oturum bulunamadı.';
  end if;

  update public.users
  set active_session_token = v_token
  where id = auth.uid();

  return v_token;
end;
$$;


ALTER FUNCTION "public"."register_active_session"() OWNER TO "postgres";


GRANT ALL ON FUNCTION "public"."register_active_session"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."register_active_session"() TO "service_role";


CREATE OR REPLACE FUNCTION "public"."check_active_session"("p_token" "uuid") RETURNS boolean
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select exists (
    select 1 from public.users
    where id = auth.uid()
      and active_session_token is not distinct from p_token
  );
$$;


ALTER FUNCTION "public"."check_active_session"("p_token" "uuid") OWNER TO "postgres";


GRANT ALL ON FUNCTION "public"."check_active_session"("p_token" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_active_session"("p_token" "uuid") TO "service_role";

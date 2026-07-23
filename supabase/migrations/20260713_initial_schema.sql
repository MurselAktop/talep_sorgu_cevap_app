-- TŞYS (Talep ve Şikâyet Yönetim Sistemi) — güncel tam şema
--
-- public şeması: 6 tablo (departments, users, requests, results, notifications,
-- personnel_invites), 29 RLS politikası (departments 3, users 5, requests 10,
-- results 4, notifications 3, personnel_invites 4); yardımcı/iş mantığı
-- fonksiyonları: current_user_role, current_user_department, handle_new_user,
-- create_request, get_request_by_token, generate_invite_code,
-- generate_access_token, sync_request_status_from_result,
-- sync_request_status_on_result_insert, mark_previously_rejected.
--
-- `docker exec supabase-db pg_dump -U postgres --schema-only --quote-all-identifier
-- --schema=public -d postgres` ile dışa aktarıldı, ardından Supabase CLI'nin
-- `supabase db dump --dry-run` çıktısındaki idempotency sed dönüşümleri
-- (CREATE SCHEMA/TABLE/SEQUENCE → IF NOT EXISTS, CREATE VIEW/FUNCTION/TRIGGER
-- → OR REPLACE, supabase_admin'e özgü ALTER DEFAULT PRIVILEGES satırlarının
-- kaldırılması) uygulandı — böylece dosya, `supabase db diff` gibi araçların
-- kurduğu boş bir shadow veritabanında hatasız yeniden oynatılabiliyor
-- (2026-07-16 tarihli oturumda doğrulandı).
--
-- auth şeması BİLİNÇLİ OLARAK dump'a dahil edilmedi: auth.* (tipler, tablolar,
-- fonksiyonlar) Supabase Auth (GoTrue) servisi tarafından yönetilir, kendi
-- migration'ımızın bunları yeniden oluşturmaya çalışması shadow veritabanında
-- "permission denied for schema auth" hatasına yol açtı (2026-07-16'da
-- denendi ve doğrulandı) — bu içerik zaten platformda mevcut ve bize ait
-- değil. Tek istisna: auth.users üzerindeki on_auth_user_created trigger'ı,
-- kendi handle_new_user() fonksiyonumuzu çağırdığı için bizim iş mantığımızın
-- bir parçasıdır ve dosyanın en sonuna elle eklendi.

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE OR REPLACE FUNCTION "public"."create_request"("p_title" "text", "p_description" "text", "p_category" "text", "p_department_id" bigint, "p_requester_type" "text", "p_created_by" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_id uuid;
  v_access_token text;
  v_actual_uid uuid := auth.uid();
  v_actual_role text;
begin
  if v_actual_uid is not null then
    select role into v_actual_role from public.users where id = v_actual_uid;
    -- Faz 4 (2026-07-21): security definer fonksiyonlar RLS'i bypass ettiği
    -- için, pasifleştirilmiş bir kullanıcının bu RPC üzerinden yeni talep
    -- açabilmesini önlemek için kontrol burada AÇIKÇA yapılmalı — RESTRICTIVE
    -- RLS politikaları bu fonksiyonun içinde hiç değerlendirilmez.
    if not public.current_user_is_active() then
      raise exception 'Hesabınız pasifleştirilmiş, yeni talep oluşturamazsınız.';
    end if;
    if p_created_by is distinct from v_actual_uid then
      raise exception 'created_by, giriş yapan kullanıcıyla eşleşmiyor.';
    end if;
    if v_actual_role = 'vatandas' and p_requester_type <> 'vatandas' then
      raise exception 'requester_type rolünüzle uyuşmuyor.';
    end if;
    if v_actual_role <> 'vatandas' and p_requester_type <> 'personel' then
      raise exception 'requester_type rolünüzle uyuşmuyor.';
    end if;
  else
    if p_created_by is not null or p_requester_type <> 'anonim' then
      raise exception 'Anonim istek için created_by boş ve requester_type anonim olmalı.';
    end if;
  end if;

  insert into requests (title, description, category, department_id, requester_type, created_by)
  values (p_title, p_description, p_category, p_department_id, p_requester_type, p_created_by)
  returning id, access_token into v_id, v_access_token;

  -- Medya ekleri Storage'a "{request_id}/..." yoluna yüklendiği için Flutter
  -- tarafının talebin id'sine de ihtiyacı var; bu yüzden dönüş tipi
  -- access_token (text) yerine {id, access_token} içeren jsonb'ye çevrildi
  -- (2026-07-17, roadmap madde 6 — medya ekleri, adım 3).
  return jsonb_build_object('id', v_id, 'access_token', v_access_token);
end;
$$;


ALTER FUNCTION "public"."create_request"("p_title" "text", "p_description" "text", "p_category" "text", "p_department_id" bigint, "p_requester_type" "text", "p_created_by" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."current_user_department"() RETURNS bigint
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select department_id from public.users where id = auth.uid();
$$;


ALTER FUNCTION "public"."current_user_department"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."current_user_role"() RETURNS "text"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select role from public.users where id = auth.uid();
$$;


ALTER FUNCTION "public"."current_user_role"() OWNER TO "postgres";


-- Faz 4 (2026-07-21): current_user_role()/current_user_department() ile aynı
-- şekil — RLS'teki recursion bug'ını atlatmak için security definer. Pasif
-- kullanıcı hesap pasifleştirmesinin RLS/RPC uygulamasında kullanılıyor.
-- coalesce ile NULL (satır bulunamazsa) true'ya düşer — böylece henüz
-- public.users satırı oluşmamış (yarış durumu) bir auth.uid() bu fonksiyon
-- yüzünden yanlışlıkla engellenmez.
CREATE OR REPLACE FUNCTION "public"."current_user_is_active"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select coalesce((select is_active from public.users where id = auth.uid()), true);
$$;


ALTER FUNCTION "public"."current_user_is_active"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_access_token"() RETURNS "text"
    LANGUAGE "plpgsql"
    AS $$
declare
  chars text := '23456789ABCDEFGHJKMNPQRSTUVWXYZ'; -- 0,1,O,I,L çıkarıldı (karışıklık yaratmasın diye)
  result text;
  i int;
begin
  loop
    result := '';
    for i in 1..8 loop
      result := result || substr(chars, floor(random() * length(chars) + 1)::int, 1);
    end loop;
    exit when not exists (select 1 from requests where access_token = result);
  end loop;
  return result;
end;
$$;


ALTER FUNCTION "public"."generate_access_token"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."generate_invite_code"() RETURNS "text"
    LANGUAGE "plpgsql"
    AS $$
declare
  chars text := '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  result text;
  i int;
begin
  loop
    result := '';
    for i in 1..8 loop
      result := result || substr(chars, floor(random() * length(chars) + 1)::int, 1);
    end loop;
    exit when not exists (select 1 from personnel_invites where code = result);
  end loop;
  return result;
end;
$$;


ALTER FUNCTION "public"."generate_invite_code"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_request_by_token"("p_access_token" "text") RETURNS TABLE("title" "text", "description" "text", "category" "text", "status" "text", "created_at" timestamp with time zone, "department_name" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  return query
  select r.title, r.description, r.category, r.status, r.created_at, d.name
  from requests r
  join departments d on d.id = r.department_id
  where r.access_token = p_access_token;
end;
$$;


ALTER FUNCTION "public"."get_request_by_token"("p_access_token" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_invite_code text;
  v_invite record;
begin
  v_invite_code := new.raw_user_meta_data ->> 'invite_code';

  if v_invite_code is not null then
    -- Personel kaydı: davet kodunu doğrula
    select * into v_invite
    from public.personnel_invites
    where code = v_invite_code
      and used = false
    for update;

    if not found then
      raise exception 'Geçersiz veya kullanılmış davet kodu.';
    end if;

    insert into public.users (id, email, full_name, role, department_id)
    values (
      new.id,
      new.email,
      new.raw_user_meta_data ->> 'full_name',
      v_invite.role,
      v_invite.department_id
    );

    update public.personnel_invites
    set used = true,
        used_by = new.id,
        used_at = now()
    where code = v_invite_code;

  else
    -- Vatandaş kaydı: eski davranış aynen korunuyor
    insert into public.users (id, email, full_name, role, department_id)
    values (
      new.id,
      new.email,
      new.raw_user_meta_data ->> 'full_name',
      'vatandas',
      null
    );
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mark_previously_rejected"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if new.approval_status = 'reddedildi' then
    new.previously_rejected = true;
  end if;
  return new;
end;
$$;


ALTER FUNCTION "public"."mark_previously_rejected"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_request_status_from_result"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_created_by uuid;
begin
  update requests
  set status = case new.approval_status
    when 'beklemede' then 'cozuldu'
    when 'onaylandi' then 'onaylandi'
    when 'reddedildi' then 'reddedildi'
    else status
  end
  where id = new.request_id
  returning created_by into v_created_by;

  if new.approval_status = 'onaylandi' and v_created_by is not null then
    insert into notifications (user_id, request_id, message)
    values (v_created_by, new.request_id, 'Talebiniz onaylandı, sonuçlandı.');
  elsif new.approval_status = 'reddedildi' then
    insert into notifications (user_id, request_id, message)
    values (new.resolved_by, new.request_id, 'Raporunuz reddedildi, lütfen yeniden inceleyin.');
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."sync_request_status_from_result"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_request_status_on_result_insert"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  update requests
  set status = 'cozuldu'
  where id = new.request_id;
  return new;
end;
$$;


ALTER FUNCTION "public"."sync_request_status_on_result_insert"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."departments" (
    "id" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "name" "text" NOT NULL
);


ALTER TABLE "public"."departments" OWNER TO "postgres";


COMMENT ON TABLE "public"."departments" IS 'Kurumdakim birimlerin verisini tutan tablo';



ALTER TABLE "public"."departments" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."departments_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



-- Faz 4 (2026-07-21): sil yerine pasifleştirme. Pasif bir birim yeni talep/
-- davet dropdown'larında görünmez (bkz. request_create_screen.dart,
-- admin_invite_screen.dart) ama geçmiş taleplerdeki adı görünmeye devam eder
-- (SELECT hâlâ herkese açık, sadece dropdown sorguları .eq('is_active', true)
-- filtresi ekliyor).
ALTER TABLE "public"."departments"
    ADD COLUMN IF NOT EXISTS "is_active" boolean DEFAULT true NOT NULL;



CREATE TABLE IF NOT EXISTS "public"."notifications" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "request_id" "uuid" NOT NULL,
    "message" "text" NOT NULL,
    "is_read" boolean DEFAULT false NOT NULL
);


ALTER TABLE "public"."notifications" OWNER TO "postgres";


COMMENT ON TABLE "public"."notifications" IS 'bildirimler (müdür onayladımı , vatandaş sonucu gördümü)';



CREATE TABLE IF NOT EXISTS "public"."personnel_invites" (
    "id" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "code" "text" DEFAULT "public"."generate_invite_code"() NOT NULL,
    "department_id" bigint NOT NULL,
    "role" "text" NOT NULL,
    "created_by" "uuid",
    "used" boolean DEFAULT false NOT NULL,
    "used_by" "uuid",
    "used_at" timestamp with time zone
);


ALTER TABLE "public"."personnel_invites" OWNER TO "postgres";


ALTER TABLE "public"."personnel_invites" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."personnel_invites_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."requests" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "title" "text" NOT NULL,
    "description" "text" NOT NULL,
    "category" "text" NOT NULL,
    "status" "text" DEFAULT 'acik'::"text" NOT NULL,
    "requester_type" "text" NOT NULL,
    "department_id" bigint NOT NULL,
    "created_by" "uuid",
    "assigned_to" "uuid",
    "access_token" "text" DEFAULT "public"."generate_access_token"() NOT NULL,
    CONSTRAINT "requests_requester_type_check" CHECK (("requester_type" = ANY (ARRAY['vatandas'::"text", 'anonim'::"text", 'personel'::"text"])))
);


ALTER TABLE "public"."requests" OWNER TO "postgres";


COMMENT ON TABLE "public"."requests" IS 'talep ve arızaların verisi';



CREATE TABLE IF NOT EXISTS "public"."results" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "report_text" "text" NOT NULL,
    "resolved_by" "uuid" NOT NULL,
    "approval_status" "text" DEFAULT 'beklemede'::"text" NOT NULL,
    "approved_by" "uuid",
    "request_id" "uuid" NOT NULL,
    "previously_rejected" boolean DEFAULT false
);


ALTER TABLE "public"."results" OWNER TO "postgres";


COMMENT ON TABLE "public"."results" IS 'sonuçlandırmalar';



CREATE TABLE IF NOT EXISTS "public"."users" (
    "id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "email" "text" NOT NULL,
    "full_name" "text" NOT NULL,
    "role" "text" NOT NULL,
    "department_id" bigint
);


ALTER TABLE "public"."users" OWNER TO "postgres";


COMMENT ON TABLE "public"."users" IS 'kullanıcılar (admin , personel , vatandaş vs)';



ALTER TABLE ONLY "public"."departments"
    ADD CONSTRAINT "departments_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."departments"
    ADD CONSTRAINT "departments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notification_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."personnel_invites"
    ADD CONSTRAINT "personnel_invites_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."requests"
    ADD CONSTRAINT "requests_access_token_key" UNIQUE ("access_token");



ALTER TABLE ONLY "public"."requests"
    ADD CONSTRAINT "requests_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."results"
    ADD CONSTRAINT "results_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."results"
    ADD CONSTRAINT "results_request_id_key" UNIQUE ("request_id");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_pkey" PRIMARY KEY ("id");



CREATE OR REPLACE TRIGGER "mark_rejected_before_update" BEFORE UPDATE ON "public"."results" FOR EACH ROW EXECUTE FUNCTION "public"."mark_previously_rejected"();



CREATE OR REPLACE TRIGGER "sync_request_status" AFTER INSERT OR UPDATE OF "approval_status" ON "public"."results" FOR EACH ROW EXECUTE FUNCTION "public"."sync_request_status_from_result"();



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_request_id_fkey" FOREIGN KEY ("request_id") REFERENCES "public"."requests"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."personnel_invites"
    ADD CONSTRAINT "personnel_invites_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."personnel_invites"
    ADD CONSTRAINT "personnel_invites_department_id_fkey" FOREIGN KEY ("department_id") REFERENCES "public"."departments"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."personnel_invites"
    ADD CONSTRAINT "personnel_invites_used_by_fkey" FOREIGN KEY ("used_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."requests"
    ADD CONSTRAINT "requests_assigned_to_fkey" FOREIGN KEY ("assigned_to") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."requests"
    ADD CONSTRAINT "requests_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."requests"
    ADD CONSTRAINT "requests_department_id_fkey" FOREIGN KEY ("department_id") REFERENCES "public"."departments"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."results"
    ADD CONSTRAINT "results_approved_by_fkey" FOREIGN KEY ("approved_by") REFERENCES "public"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."results"
    ADD CONSTRAINT "results_request_id_fkey" FOREIGN KEY ("request_id") REFERENCES "public"."requests"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."results"
    ADD CONSTRAINT "results_resolved_by_fkey" FOREIGN KEY ("resolved_by") REFERENCES "public"."users"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_department_id_fkey" FOREIGN KEY ("department_id") REFERENCES "public"."departments"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



CREATE POLICY "Adminler davet kodu oluşturabilir" ON "public"."personnel_invites" FOR INSERT WITH CHECK (("public"."current_user_role"() = 'admin'::"text"));



CREATE POLICY "Adminler davet kodunu güncelleyebilir" ON "public"."personnel_invites" FOR UPDATE USING (("public"."current_user_role"() = 'admin'::"text")) WITH CHECK (("public"."current_user_role"() = 'admin'::"text"));



CREATE POLICY "Adminler davet kodunu silebilir" ON "public"."personnel_invites" FOR DELETE USING (("public"."current_user_role"() = 'admin'::"text"));



CREATE POLICY "Adminler tüm davet kodlarını görebilir" ON "public"."personnel_invites" FOR SELECT USING (("public"."current_user_role"() = 'admin'::"text"));



CREATE POLICY "Birimlerin Görünürlüğü" ON "public"."departments" FOR SELECT USING (true);



CREATE POLICY "acan_kisi_henuz_atanmamisken_duzenleyebilir" ON "public"."requests" FOR UPDATE USING ((("created_by" = "auth"."uid"()) AND ("assigned_to" IS NULL))) WITH CHECK ((("created_by" = "auth"."uid"()) AND ("assigned_to" IS NULL)));



CREATE POLICY "acan_kisi_kendi_talebini_gorebilir" ON "public"."requests" FOR SELECT USING (("created_by" = "auth"."uid"()));



CREATE POLICY "admin_hepsini_gorebilir" ON "public"."requests" FOR SELECT USING ((( SELECT "users"."role"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"())) = 'admin'::"text"));



CREATE POLICY "admin_her_seyi_guncelleyebilir" ON "public"."requests" FOR UPDATE USING ((( SELECT "users"."role"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"())) = 'admin'::"text")) WITH CHECK ((( SELECT "users"."role"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"())) = 'admin'::"text"));



CREATE POLICY "admin_herkesi_gorebilir" ON "public"."users" FOR SELECT USING (("public"."current_user_role"() = 'admin'::"text"));



CREATE POLICY "admin_tum_talepleri_gorebilir" ON "public"."requests" FOR SELECT TO "authenticated" USING (("public"."current_user_role"() = 'admin'::"text"));



CREATE POLICY "anonim_kullanici_talep_acabilir" ON "public"."requests" FOR INSERT TO "anon" WITH CHECK (("created_by" IS NULL));



CREATE POLICY "atanan_personel_duzenleyebilir" ON "public"."results" FOR UPDATE TO "authenticated" USING ((("resolved_by" = "auth"."uid"()) AND ("approval_status" = ANY (ARRAY['beklemede'::"text", 'reddedildi'::"text"])))) WITH CHECK ((("resolved_by" = "auth"."uid"()) AND ("approval_status" = 'beklemede'::"text")));



CREATE POLICY "atanan_personel_rapor_ekleyebilir" ON "public"."results" FOR INSERT WITH CHECK ((("resolved_by" = "auth"."uid"()) AND (EXISTS ( SELECT 1
   FROM "public"."requests"
  WHERE (("requests"."id" = "results"."request_id") AND ("requests"."assigned_to" = "auth"."uid"()))))));



ALTER TABLE "public"."departments" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "giris_yapmis_herkes_talep_acabilir" ON "public"."requests" FOR INSERT WITH CHECK (("created_by" = "auth"."uid"()));



CREATE POLICY "ilgili_talebi_gorebilen_sonucu_gorebilir" ON "public"."results" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."requests"
  WHERE (("requests"."id" = "results"."request_id") AND (("requests"."created_by" = "auth"."uid"()) OR (("requests"."department_id" = ( SELECT "users"."department_id"
           FROM "public"."users"
          WHERE ("users"."id" = "auth"."uid"()))) AND (( SELECT "users"."role"
           FROM "public"."users"
          WHERE ("users"."id" = "auth"."uid"())) = ANY (ARRAY['personel'::"text", 'mudur'::"text"]))) OR (( SELECT "users"."role"
           FROM "public"."users"
          WHERE ("users"."id" = "auth"."uid"())) = 'admin'::"text"))))));



CREATE POLICY "kendi_bildirimini_gorebilir" ON "public"."notifications" FOR SELECT USING (("user_id" = "auth"."uid"()));



CREATE POLICY "kendi_bildirimini_okundu_yapabilir" ON "public"."notifications" FOR UPDATE USING (("user_id" = "auth"."uid"())) WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "kendi_kaydini_olusturabilir" ON "public"."users" FOR INSERT WITH CHECK (("id" = "auth"."uid"()));



CREATE POLICY "kendi_profilini_görebilir" ON "public"."users" FOR SELECT USING (("id" = "auth"."uid"()));



CREATE POLICY "kendi_profilini_güncelleyebilir" ON "public"."users" FOR UPDATE USING (("id" = "auth"."uid"())) WITH CHECK ((("id" = "auth"."uid"()) AND ("role" = ( SELECT "users_1"."role"
   FROM "public"."users" "users_1"
  WHERE ("users_1"."id" = "auth"."uid"()))) AND (NOT ("department_id" IS DISTINCT FROM ( SELECT "users_1"."department_id"
   FROM "public"."users" "users_1"
  WHERE ("users_1"."id" = "auth"."uid"()))))));



CREATE POLICY "mudur_biriminin_personelini_gorebilir" ON "public"."users" FOR SELECT USING ((("department_id" = "public"."current_user_department"()) AND ("public"."current_user_role"() = 'mudur'::"text")));



CREATE POLICY "mudur_biriminin_tum_taleplerini_gorebilir" ON "public"."requests" FOR SELECT TO "authenticated" USING ((("public"."current_user_role"() = 'mudur'::"text") AND (NOT ("department_id" IS DISTINCT FROM "public"."current_user_department"()))));



CREATE POLICY "mudur_durum_ve_atama_guncelleyebilir" ON "public"."requests" FOR UPDATE USING ((("department_id" = ( SELECT "users"."department_id"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"()))) AND (( SELECT "users"."role"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"())) = 'mudur'::"text"))) WITH CHECK ((("department_id" = ( SELECT "users"."department_id"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"()))) AND (( SELECT "users"."role"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"())) = 'mudur'::"text")));



CREATE POLICY "mudur_onay_verebilir" ON "public"."results" FOR UPDATE USING (((( SELECT "users"."role"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"())) = 'mudur'::"text") AND (EXISTS ( SELECT 1
   FROM "public"."requests"
  WHERE (("requests"."id" = "results"."request_id") AND ("requests"."department_id" = ( SELECT "users"."department_id"
           FROM "public"."users"
          WHERE ("users"."id" = "auth"."uid"())))))))) WITH CHECK (((( SELECT "users"."role"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"())) = 'mudur'::"text") AND (EXISTS ( SELECT 1
   FROM "public"."requests"
  WHERE (("requests"."id" = "results"."request_id") AND ("requests"."department_id" = ( SELECT "users"."department_id"
           FROM "public"."users"
          WHERE ("users"."id" = "auth"."uid"()))))))));



ALTER TABLE "public"."notifications" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "personel_atanan_talepleri_gorebilir" ON "public"."requests" FOR SELECT TO "authenticated" USING ((("public"."current_user_role"() = 'personel'::"text") AND ("assigned_to" = "auth"."uid"())));



ALTER TABLE "public"."personnel_invites" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."requests" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."results" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sadece_admin_ekleyebilir" ON "public"."departments" FOR INSERT WITH CHECK ((( SELECT "users"."role"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"())) = 'admin'::"text"));



CREATE POLICY "sadece_admin_güncelleyebilir" ON "public"."departments" FOR UPDATE USING ((( SELECT "users"."role"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"())) = 'admin'::"text")) WITH CHECK ((( SELECT "users"."role"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"())) = 'admin'::"text"));



CREATE POLICY "sistem_bildirim_ekleyebilir" ON "public"."notifications" FOR INSERT WITH CHECK (false);



ALTER TABLE "public"."users" ENABLE ROW LEVEL SECURITY;


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON FUNCTION "public"."create_request"("p_title" "text", "p_description" "text", "p_category" "text", "p_department_id" bigint, "p_requester_type" "text", "p_created_by" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."create_request"("p_title" "text", "p_description" "text", "p_category" "text", "p_department_id" bigint, "p_requester_type" "text", "p_created_by" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_request"("p_title" "text", "p_description" "text", "p_category" "text", "p_department_id" bigint, "p_requester_type" "text", "p_created_by" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."current_user_department"() TO "anon";
GRANT ALL ON FUNCTION "public"."current_user_department"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."current_user_department"() TO "service_role";



GRANT ALL ON FUNCTION "public"."current_user_role"() TO "anon";
GRANT ALL ON FUNCTION "public"."current_user_role"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."current_user_role"() TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_access_token"() TO "anon";
GRANT ALL ON FUNCTION "public"."generate_access_token"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_access_token"() TO "service_role";



GRANT ALL ON FUNCTION "public"."generate_invite_code"() TO "anon";
GRANT ALL ON FUNCTION "public"."generate_invite_code"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."generate_invite_code"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_request_by_token"("p_access_token" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_request_by_token"("p_access_token" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_request_by_token"("p_access_token" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "service_role";



GRANT ALL ON FUNCTION "public"."mark_previously_rejected"() TO "anon";
GRANT ALL ON FUNCTION "public"."mark_previously_rejected"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."mark_previously_rejected"() TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_request_status_from_result"() TO "anon";
GRANT ALL ON FUNCTION "public"."sync_request_status_from_result"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_request_status_from_result"() TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_request_status_on_result_insert"() TO "anon";
GRANT ALL ON FUNCTION "public"."sync_request_status_on_result_insert"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_request_status_on_result_insert"() TO "service_role";



GRANT ALL ON TABLE "public"."departments" TO "anon";
GRANT ALL ON TABLE "public"."departments" TO "authenticated";
GRANT ALL ON TABLE "public"."departments" TO "service_role";



GRANT ALL ON SEQUENCE "public"."departments_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."departments_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."departments_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."notifications" TO "anon";
GRANT ALL ON TABLE "public"."notifications" TO "authenticated";
GRANT ALL ON TABLE "public"."notifications" TO "service_role";



GRANT ALL ON TABLE "public"."personnel_invites" TO "anon";
GRANT ALL ON TABLE "public"."personnel_invites" TO "authenticated";
GRANT ALL ON TABLE "public"."personnel_invites" TO "service_role";



GRANT ALL ON SEQUENCE "public"."personnel_invites_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."personnel_invites_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."personnel_invites_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."requests" TO "anon";
GRANT ALL ON TABLE "public"."requests" TO "authenticated";
GRANT ALL ON TABLE "public"."requests" TO "service_role";



GRANT ALL ON TABLE "public"."results" TO "anon";
GRANT ALL ON TABLE "public"."results" TO "authenticated";
GRANT ALL ON TABLE "public"."results" TO "service_role";



GRANT ALL ON TABLE "public"."users" TO "anon";
GRANT ALL ON TABLE "public"."users" TO "authenticated";
GRANT ALL ON TABLE "public"."users" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";






--
-- Name: users on_auth_user_created; Type: TRIGGER; Schema: auth; Owner: -
--
-- auth.users, Supabase Auth (GoTrue) tarafından yönetilen bir tablodur ve
-- pg_dump --schema=public kapsamının dışındadır; bu trigger sadece bizim
-- eklediğimiz özel iş mantığı olduğu için elle buraya taşındı.
--

drop trigger if exists on_auth_user_created on auth.users;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();


--
-- Medya ekleri (attachments) — Roadmap madde 6, backend tarafı (2026-07-17).
-- public.attachments tablosu + RLS bu bölümde; ardından Storage bucket'ı ve
-- storage.objects RLS politikaları. storage şeması (bucket, objects), auth
-- şeması gibi Supabase tarafından yönetilir ve pg_dump --schema=public
-- kapsamının dışındadır; auth.users trigger'ında olduğu gibi elle eklendi
-- (bu bölüm gerçek bir pg_dump çıktısı değil, elle yazıldı).
--
-- Yükleme yolu kuralı: dosyalar Storage'a "{request_id}/{dosya_adı}"
-- şeklinde yüklenmeli — storage.objects politikaları request_id'yi bu
-- yoldan (storage.foldername) okuyup ilgili talebin görünürlük/atama
-- kurallarını uyguluyor.
--

CREATE TABLE IF NOT EXISTS "public"."attachments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "request_id" "uuid" NOT NULL,
    "file_url" "text" NOT NULL,
    "media_type" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "attachments_media_type_check" CHECK (("media_type" = ANY (ARRAY['image'::"text", 'video'::"text", 'document'::"text"])))
);


ALTER TABLE "public"."attachments" OWNER TO "postgres";


COMMENT ON TABLE "public"."attachments" IS 'talep foto/video/belge ekleri (Supabase Storage''daki dosyaların meta verisi)';


ALTER TABLE ONLY "public"."attachments"
    ADD CONSTRAINT "attachments_pkey" PRIMARY KEY ("id");


ALTER TABLE ONLY "public"."attachments"
    ADD CONSTRAINT "attachments_request_id_fkey" FOREIGN KEY ("request_id") REFERENCES "public"."requests"("id") ON DELETE CASCADE;


ALTER TABLE "public"."attachments" ENABLE ROW LEVEL SECURITY;


-- SELECT: ilgili talebi görebilen herkes (açan kişi / müdür / atanan
-- personel / admin) ekleri de görebilir — results tablosundakiyle aynı
-- "ilgili talebi görebilen" mantığı.
CREATE POLICY "ilgili_talebi_gorebilen_ekleri_gorebilir" ON "public"."attachments" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."requests" "r"
  WHERE (("r"."id" = "attachments"."request_id") AND (("r"."created_by" = "auth"."uid"()) OR (("public"."current_user_role"() = 'mudur'::"text") AND (NOT ("r"."department_id" IS DISTINCT FROM "public"."current_user_department"()))) OR (("public"."current_user_role"() = 'personel'::"text") AND ("r"."assigned_to" = "auth"."uid"())) OR ("public"."current_user_role"() = 'admin'::"text"))))));


-- INSERT: talebi açan kişi, atanan personel veya admin ek ekleyebilir.
CREATE POLICY "acan_kisi_atanan_personel_veya_admin_ek_ekleyebilir" ON "public"."attachments" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."requests" "r"
  WHERE (("r"."id" = "attachments"."request_id") AND (("r"."created_by" = "auth"."uid"()) OR ("r"."assigned_to" = "auth"."uid"()) OR ("public"."current_user_role"() = 'admin'::"text"))))));


GRANT ALL ON TABLE "public"."attachments" TO "anon";
GRANT ALL ON TABLE "public"."attachments" TO "authenticated";
GRANT ALL ON TABLE "public"."attachments" TO "service_role";


--
-- Storage: request-attachments bucket'ı (private) + storage.objects RLS.
--

INSERT INTO "storage"."buckets" ("id", "name", "public", "file_size_limit", "allowed_mime_types")
VALUES (
  'request-attachments',
  'request-attachments',
  false,
  52428800,
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'video/mp4', 'video/quicktime', 'application/pdf', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document']
)
ON CONFLICT ("id") DO NOTHING;


-- SELECT (indirme/görme): ilgili talebi görebilen herkes dosyayı da görebilir.
CREATE POLICY "ilgili_talebi_gorebilen_dosyayi_gorebilir" ON "storage"."objects" FOR SELECT USING ((("bucket_id" = 'request-attachments'::"text") AND (EXISTS ( SELECT 1
   FROM "public"."requests" "r"
  WHERE (("r"."id"::"text" = ("storage"."foldername"("objects"."name"))[1]) AND (("r"."created_by" = "auth"."uid"()) OR (("public"."current_user_role"() = 'mudur'::"text") AND (NOT ("r"."department_id" IS DISTINCT FROM "public"."current_user_department"()))) OR (("public"."current_user_role"() = 'personel'::"text") AND ("r"."assigned_to" = "auth"."uid"())) OR ("public"."current_user_role"() = 'admin'::"text")))))));


-- INSERT (yükleme): talebi açan kişi, atanan personel veya admin dosya yükleyebilir.
CREATE POLICY "acan_kisi_atanan_personel_veya_admin_dosya_yukleyebilir" ON "storage"."objects" FOR INSERT WITH CHECK ((("bucket_id" = 'request-attachments'::"text") AND (EXISTS ( SELECT 1
   FROM "public"."requests" "r"
  WHERE (("r"."id"::"text" = ("storage"."foldername"("objects"."name"))[1]) AND (("r"."created_by" = "auth"."uid"()) OR ("r"."assigned_to" = "auth"."uid"()) OR ("public"."current_user_role"() = 'admin'::"text")))))));


--
-- Genişletme Faz 1 — Veri modeli + kayıt ekranı genişletmesi (2026-07-20).
-- users tablosuna phone/il/ilce eklendi; tc_no ayrı bir users_private
-- tablosuna kondu. Sebep: RLS satır bazlıdır, sütun gizleyemez — müdür,
-- birim personelinin users satırını görebildiği için tc_no aynı tabloda
-- olsaydı müdür de görürdü. Karar (2026-07-20): tc_no'yu SADECE kullanıcının
-- kendisi + admin görebilir. KVKK onay alanı (kvkk_accepted_at) bilinçli
-- olarak Faz 1 kapsamından çıkarıldı; production öncesi eklenecek.
-- (Bu bölüm elle yazıldı, pg_dump çıktısı değildir.)
--

ALTER TABLE "public"."users"
    ADD COLUMN IF NOT EXISTS "phone" "text",
    ADD COLUMN IF NOT EXISTS "il" "text",
    ADD COLUMN IF NOT EXISTS "ilce" "text";

-- Sütunlar bilinçli olarak NULLABLE: mevcut hesaplarda bu bilgiler yok.
-- Yeni kayıtlar için zorunluluk handle_new_user() trigger'ında ve Flutter
-- formunda uygulanıyor.

-- Faz 4 (2026-07-21): sil yerine pasifleştirme. Pasif bir kullanıcı giriş
-- yapabilir ama hiçbir okuma/yazma işlemi yapamaz — bkz. current_user_is_active()
-- ve bu dosyanın sonundaki RESTRICTIVE politikalar bölümü. "own row" için
-- SELECT bilinçli olarak açık bırakılıyor (login_screen.dart/home_screen.dart
-- kendi is_active durumunu okuyup temiz bir Türkçe mesajla çıkış yapabilsin diye).
ALTER TABLE "public"."users"
    ADD COLUMN IF NOT EXISTS "is_active" boolean DEFAULT true NOT NULL;

CREATE TABLE IF NOT EXISTS "public"."users_private" (
    "user_id" "uuid" NOT NULL,
    "tc_no" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "users_private_pkey" PRIMARY KEY ("user_id"),
    CONSTRAINT "users_private_tc_no_key" UNIQUE ("tc_no"),
    CONSTRAINT "users_private_tc_no_format" CHECK (("tc_no" ~ '^[1-9][0-9]{10}$'))
);


ALTER TABLE "public"."users_private" OWNER TO "postgres";


COMMENT ON TABLE "public"."users_private" IS 'hassas kimlik bilgileri (tc_no) — RLS: sadece kullanıcının kendisi + admin okuyabilir';


ALTER TABLE ONLY "public"."users_private"
    ADD CONSTRAINT "users_private_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;


ALTER TABLE "public"."users_private" ENABLE ROW LEVEL SECURITY;


-- SELECT: sadece kullanıcının kendisi + admin.
CREATE POLICY "kendi_tc_bilgisini_gorebilir" ON "public"."users_private" FOR SELECT USING (("user_id" = "auth"."uid"()));


CREATE POLICY "admin_tc_bilgilerini_gorebilir" ON "public"."users_private" FOR SELECT USING (("public"."current_user_role"() = 'admin'::"text"));


-- BİLİNÇLİ: INSERT/UPDATE/DELETE politikası YOK. Satırı yalnızca
-- handle_new_user() (security definer, RLS'i aşar) ekler; T.C. kimlik no
-- sonradan değişmeyeceği için uygulama üzerinden kimse (admin dahil)
-- güncelleyemez/silemez. Düzeltme gerekirse doğrudan SQL ile yapılır.

GRANT ALL ON TABLE "public"."users_private" TO "anon";
GRANT ALL ON TABLE "public"."users_private" TO "authenticated";
GRANT ALL ON TABLE "public"."users_private" TO "service_role";


-- handle_new_user(): Faz 1 için genişletildi — tc_no/phone/il/ilce metadata
-- alanları YENİ kayıtlar için zorunlu; phone/il/ilce public.users'a, tc_no
-- public.users_private'a yazılıyor. İki tabloya yazım aynı trigger içinde
-- olduğu için atomik: users_private insert'i başarısız olursa tüm kayıt
-- (auth.users satırı dahil) geri alınır, yarım profil kalmaz.
CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_invite_code text;
  v_invite record;
  v_tc_no text;
  v_phone text;
  v_il text;
  v_ilce text;
begin
  v_invite_code := new.raw_user_meta_data ->> 'invite_code';
  v_tc_no := nullif(trim(new.raw_user_meta_data ->> 'tc_no'), '');
  v_phone := nullif(trim(new.raw_user_meta_data ->> 'phone'), '');
  v_il    := nullif(trim(new.raw_user_meta_data ->> 'il'), '');
  v_ilce  := nullif(trim(new.raw_user_meta_data ->> 'ilce'), '');

  -- Zorunluluk kontrolü trigger'da da var ki Flutter formunu atlayıp
  -- doğrudan Auth API'ye istek atan biri eksik profille hesap açamasın.
  if v_tc_no is null or v_phone is null or v_il is null or v_ilce is null then
    raise exception 'Kayıt için T.C. kimlik no, telefon, il ve ilçe zorunludur.';
  end if;

  if v_invite_code is not null then
    -- Personel kaydı: davet kodunu doğrula
    select * into v_invite
    from public.personnel_invites
    where code = v_invite_code
      and used = false
    for update;

    if not found then
      raise exception 'Geçersiz veya kullanılmış davet kodu.';
    end if;

    insert into public.users (id, email, full_name, role, department_id, phone, il, ilce)
    values (
      new.id,
      new.email,
      new.raw_user_meta_data ->> 'full_name',
      v_invite.role,
      v_invite.department_id,
      v_phone,
      v_il,
      v_ilce
    );

    update public.personnel_invites
    set used = true,
        used_by = new.id,
        used_at = now()
    where code = v_invite_code;

  else
    -- Vatandaş kaydı
    insert into public.users (id, email, full_name, role, department_id, phone, il, ilce)
    values (
      new.id,
      new.email,
      new.raw_user_meta_data ->> 'full_name',
      'vatandas',
      null,
      v_phone,
      v_il,
      v_ilce
    );
  end if;

  -- tc_no ayrı, kısıtlı erişimli tabloya. UNIQUE/CHECK ihlallerini Türkçe
  -- mesaja çeviriyoruz ki Flutter tarafı inline alan hatası gösterebilsin.
  begin
    insert into public.users_private (user_id, tc_no)
    values (new.id, v_tc_no);
  exception
    when unique_violation then
      raise exception 'Bu T.C. kimlik numarası ile zaten bir hesap mevcut.';
    when check_violation then
      raise exception 'Geçersiz T.C. kimlik numarası formatı.';
  end;

  return new;
end;
$$;



--
-- check_registration_availability — 2026-07-20, kayıt öncesi doğrulama RPC'si.
--
-- KÖK NEDEN: GoTrue'nun (gotrue Dart paketi) her /signup isteğine otomatik
-- eklediği "X-Supabase-Api-Version: 2024-01-01" header'ı, sunucudaki GoTrue'yu
-- handle_new_user() trigger'ından gelen HER türlü özel Postgres hatasını
-- (tc_no format/çakışma, eksik alan, geçersiz davet kodu — hepsi) generic bir
-- mesaja sarmalamaya zorluyor: {"code":"unexpected_failure","message":
-- "Database error saving new user"}. Bu, gotrue paketi seviyesinde sabit bir
-- davranış; bizim tarafımızdan kapatılamaz veya bypass edilemez.
--
-- ÇÖZÜM: Bu kontroller artık signUp()'tan ÖNCE, ayrı bir RPC ile yapılıyor.
-- RPC çağrıları Postgrest üzerinden gider (GoTrue'nun /signup sanitizasyonuna
-- hiç girmez), bu yüzden gerçek Türkçe hata mesajı PostgrestException.message
-- olarak sorunsuz döner. handle_new_user() trigger'ındaki kontroller AYNEN
-- KALIYOR — nihai güvenlik ağı (bir yarış durumunda bu RPC geçse bile trigger
-- yine reddeder, o nadir durumda kullanıcı generic mesaj görür ama veri
-- bütünlüğü bozulmaz).
--

CREATE OR REPLACE FUNCTION "public"."check_registration_availability"("p_tc_no" "text", "p_invite_code" "text" DEFAULT NULL) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_invite record;
begin
  if p_tc_no !~ '^[1-9][0-9]{10}$' then
    raise exception 'Geçersiz T.C. kimlik numarası formatı.';
  end if;

  if exists (select 1 from public.users_private where tc_no = p_tc_no) then
    raise exception 'Bu T.C. kimlik numarası ile zaten bir hesap mevcut.';
  end if;

  if p_invite_code is not null then
    select * into v_invite
    from public.personnel_invites
    where code = p_invite_code
      and used = false;

    if not found then
      raise exception 'Geçersiz veya kullanılmış davet kodu.';
    end if;
  end if;
end;
$$;


ALTER FUNCTION "public"."check_registration_availability"("p_tc_no" "text", "p_invite_code" "text") OWNER TO "postgres";


GRANT ALL ON FUNCTION "public"."check_registration_availability"("p_tc_no" "text", "p_invite_code" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."check_registration_availability"("p_tc_no" "text", "p_invite_code" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_registration_availability"("p_tc_no" "text", "p_invite_code" "text") TO "service_role";


--
-- Faz 4 (2026-07-21) — Hesap pasifleştirme: admin_set_user_active() RPC.
--
-- Genel bir "admin herkesi güncelleyebilir" RLS politikası YERİNE bilinçli
-- olarak dar kapsamlı bir RPC tercih edildi: geniş bir politika, role/
-- department_id gibi başka alanları da REST üzerinden değiştirilebilir hale
-- getirip CLAUDE.md'nin bilinçli olarak ertelediği "admin rol yükseltme
-- arayüzü" özelliğini yan kapıdan açardı. Bu RPC SADECE is_active sütununa
-- dokunur. Adminin kendi hesabını pasifleştirip kilitlenmesini önlemek için
-- p_user_id = auth.uid() reddedilir.
--

CREATE OR REPLACE FUNCTION "public"."admin_set_user_active"("p_user_id" "uuid", "p_is_active" boolean) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if not public.current_user_is_active() then
    raise exception 'Hesabınız pasifleştirilmiş, bu işlemi yapamazsınız.';
  end if;
  if public.current_user_role() <> 'admin' then
    raise exception 'Bu işlem için admin yetkisi gerekir.';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'Kendi hesabınızı pasifleştiremezsiniz.';
  end if;

  update public.users set is_active = p_is_active where id = p_user_id;
  if not found then
    raise exception 'Kullanıcı bulunamadı.';
  end if;
end;
$$;


ALTER FUNCTION "public"."admin_set_user_active"("p_user_id" "uuid", "p_is_active" boolean) OWNER TO "postgres";


GRANT ALL ON FUNCTION "public"."admin_set_user_active"("p_user_id" "uuid", "p_is_active" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_set_user_active"("p_user_id" "uuid", "p_is_active" boolean) TO "service_role";


--
-- Faz 4 (2026-07-21) — Hesap pasifleştirme: RESTRICTIVE RLS politikaları.
--
-- ÖNEMLİ: SECURITY DEFINER fonksiyonlar (create_request, admin_set_user_active,
-- reassign_request_department vb.) RLS'i tamamen bypass eder (fonksiyon
-- sahibi postgres, tablolarda FORCE ROW LEVEL SECURITY yok) — bu yüzden
-- aşağıdaki politikalar sadece doğrudan .from(table).select/insert/update()
-- çağrılarını korur; her RPC'nin içine current_user_is_active() kontrolü
-- AYRICA elle eklenmesi gerekir (create_request() için yukarıda yapıldı).
--
-- Mevcut ~25 permissive politikayı tek tek değiştirmek yerine (büyük, hataya
-- açık bir yüzey) her tabloya EK bir "AS RESTRICTIVE" politika ekleniyor —
-- bunlar OR'lanmış permissive kümesiyle AND'lenir, mevcut politikalara hiç
-- dokunulmuyor. users/requests/results/notifications tablolarında "kendi
-- satırım" için bilinçli bir carve-out var (id/created_by/resolved_by/user_id
-- = auth.uid() OR current_user_is_active()) — pasif bir kullanıcı kendi
-- geçmiş verisini görmeye devam eder (CLAUDE.md'nin "giriş/işlem yapamaması"
-- ifadesi bir eylem/yazma kısıtlaması olarak yorumlandı), ama YAZMA
-- (INSERT/UPDATE) her durumda tamamen kapanıyor. personnel_invites/
-- attachments'ta carve-out yok (admin-only veya dolaylı erişim tabloları).
--

-- users: kendi satırını okumak HER ZAMAN serbest (login/home_screen'in kendi
-- is_active kontrolü hiç bozulmasın diye — aksi halde pasif bir kullanıcı
-- temiz bir mesaj yerine "satır bulunamadı" hatasıyla karşılaşırdı), ama
-- müdürün-birim-personeli-görmesi/admin-herkesi-görmesi pasifken kapanır.
CREATE POLICY "pasif_kullanici_sinirlamasi_select" ON "public"."users" AS RESTRICTIVE FOR SELECT USING ((("id" = "auth"."uid"()) OR "public"."current_user_is_active"()));
CREATE POLICY "pasif_kullanici_sinirlamasi_update" ON "public"."users" AS RESTRICTIVE FOR UPDATE USING ("public"."current_user_is_active"()) WITH CHECK ("public"."current_user_is_active"());

-- requests: kendi açtığı talebi görmeye devam eder, yazma tamamen kapanır.
CREATE POLICY "pasif_kullanici_sinirlamasi_select" ON "public"."requests" AS RESTRICTIVE FOR SELECT TO "authenticated" USING ((("created_by" = "auth"."uid"()) OR "public"."current_user_is_active"()));
CREATE POLICY "pasif_kullanici_sinirlamasi_insert" ON "public"."requests" AS RESTRICTIVE FOR INSERT TO "authenticated" WITH CHECK ("public"."current_user_is_active"());
CREATE POLICY "pasif_kullanici_sinirlamasi_update" ON "public"."requests" AS RESTRICTIVE FOR UPDATE TO "authenticated" USING ("public"."current_user_is_active"()) WITH CHECK ("public"."current_user_is_active"());

-- results: kendi çözdüğü raporu görmeye devam eder (resolved_by), yazma kapanır.
CREATE POLICY "pasif_kullanici_sinirlamasi_select" ON "public"."results" AS RESTRICTIVE FOR SELECT USING ((("resolved_by" = "auth"."uid"()) OR "public"."current_user_is_active"()));
CREATE POLICY "pasif_kullanici_sinirlamasi_insert" ON "public"."results" AS RESTRICTIVE FOR INSERT WITH CHECK ("public"."current_user_is_active"());
CREATE POLICY "pasif_kullanici_sinirlamasi_update" ON "public"."results" AS RESTRICTIVE FOR UPDATE USING ("public"."current_user_is_active"()) WITH CHECK ("public"."current_user_is_active"());

-- notifications: kendi bildirimini görmeye devam eder, okundu işaretleme kapanır.
CREATE POLICY "pasif_kullanici_sinirlamasi_select" ON "public"."notifications" AS RESTRICTIVE FOR SELECT USING ((("user_id" = "auth"."uid"()) OR "public"."current_user_is_active"()));
CREATE POLICY "pasif_kullanici_sinirlamasi_update" ON "public"."notifications" AS RESTRICTIVE FOR UPDATE USING ("public"."current_user_is_active"()) WITH CHECK ("public"."current_user_is_active"());

-- personnel_invites: admin-only tablo, carve-out yok.
CREATE POLICY "pasif_kullanici_sinirlamasi_select" ON "public"."personnel_invites" AS RESTRICTIVE FOR SELECT USING ("public"."current_user_is_active"());
CREATE POLICY "pasif_kullanici_sinirlamasi_insert" ON "public"."personnel_invites" AS RESTRICTIVE FOR INSERT WITH CHECK ("public"."current_user_is_active"());
CREATE POLICY "pasif_kullanici_sinirlamasi_update" ON "public"."personnel_invites" AS RESTRICTIVE FOR UPDATE USING ("public"."current_user_is_active"()) WITH CHECK ("public"."current_user_is_active"());
CREATE POLICY "pasif_kullanici_sinirlamasi_delete" ON "public"."personnel_invites" AS RESTRICTIVE FOR DELETE USING ("public"."current_user_is_active"());

-- attachments: dolaylı erişim tablosu, carve-out yok.
CREATE POLICY "pasif_kullanici_sinirlamasi_select" ON "public"."attachments" AS RESTRICTIVE FOR SELECT USING ("public"."current_user_is_active"());
CREATE POLICY "pasif_kullanici_sinirlamasi_insert" ON "public"."attachments" AS RESTRICTIVE FOR INSERT WITH CHECK ("public"."current_user_is_active"());


--
-- Faz 4 (2026-07-21) — Talep yönlendirme: request_department_reassignments
-- tablosu + reassign_request_department() RPC.
--
-- Müdürün mevcut "mudur_durum_ve_atama_guncelleyebilir" UPDATE politikasının
-- HEM USING HEM WITH CHECK yan tümcesi department_id = current_user_department()
-- içeriyor — yani bir talebi BAŞKA birime taşıyan düz bir UPDATE, yeni satırın
-- department_id'si müdürün kendi birimiyle eşleşmediği için WITH CHECK
-- tarafından reddedilir. Bu yüzden security definer bir RPC şart.
--

CREATE TABLE IF NOT EXISTS "public"."request_department_reassignments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "request_id" "uuid" NOT NULL,
    "old_department_id" bigint NOT NULL,
    "new_department_id" bigint NOT NULL,
    "reassigned_by" "uuid",
    "reassigned_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

COMMENT ON TABLE "public"."request_department_reassignments" IS 'Müdürün bir talebi başka birime yönlendirme geçmişi (kim, ne zaman, hangi birimden hangi birime) — sadece reassign_request_department() RPC''si tarafından yazılır.';

ALTER TABLE "public"."request_department_reassignments" OWNER TO "postgres";

ALTER TABLE ONLY "public"."request_department_reassignments"
    ADD CONSTRAINT "request_department_reassignments_pkey" PRIMARY KEY ("id");

-- request_id → requests.id: ON DELETE CASCADE — talep silinirse (şu an bir
-- silme akışı yok ama gelecekte olursa) yönlendirme geçmişinin anlamı kalmaz.
ALTER TABLE ONLY "public"."request_department_reassignments"
    ADD CONSTRAINT "request_department_reassignments_request_id_fkey" FOREIGN KEY ("request_id") REFERENCES "public"."requests"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."request_department_reassignments"
    ADD CONSTRAINT "request_department_reassignments_old_department_id_fkey" FOREIGN KEY ("old_department_id") REFERENCES "public"."departments"("id");

ALTER TABLE ONLY "public"."request_department_reassignments"
    ADD CONSTRAINT "request_department_reassignments_new_department_id_fkey" FOREIGN KEY ("new_department_id") REFERENCES "public"."departments"("id");

-- reassigned_by → users.id: ON DELETE SET NULL — personnel_invites'taki
-- created_by/used_by kararıyla aynı gerekçe: hesap silinirse geçmiş kaydı
-- silinmez, sadece "kim yaptı" bilgisi NULL olur.
ALTER TABLE ONLY "public"."request_department_reassignments"
    ADD CONSTRAINT "request_department_reassignments_reassigned_by_fkey" FOREIGN KEY ("reassigned_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;

ALTER TABLE "public"."request_department_reassignments" ENABLE ROW LEVEL SECURITY;

-- Sadece admin görebilir (kullanıcı kararı: müdürlere görünürlük bu fazda
-- eklenmiyor, UI'da da hiç tüketilmiyor — ileride genişletilebilir). İstemciden
-- hiç INSERT/UPDATE/DELETE politikası YOK, sadece RPC (security definer) yazar.
CREATE POLICY "sadece_admin_gorebilir" ON "public"."request_department_reassignments" FOR SELECT USING (("public"."current_user_role"() = 'admin'::"text"));


CREATE OR REPLACE FUNCTION "public"."reassign_request_department"("p_request_id" "uuid", "p_new_department_id" bigint) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_request record;
  v_target_department record;
begin
  if not public.current_user_is_active() then
    raise exception 'Hesabınız pasifleştirilmiş, bu işlemi yapamazsınız.';
  end if;

  -- FOR UPDATE: personel aynı anda raporu çözerken müdür yönlendirirse
  -- oluşabilecek yarış durumunu önlemek için satır kilitleniyor; status
  -- kontrolü kilit ALINDIKTAN SONRA yapılıyor (personnel_invites'taki
  -- "for update" deseniyle aynı, bkz. handle_new_user()).
  select * into v_request from public.requests where id = p_request_id for update;
  if not found then
    raise exception 'Talep bulunamadı.';
  end if;

  if v_request.status <> 'acik' then
    raise exception 'Sadece açık durumdaki talepler başka birime yönlendirilebilir.';
  end if;

  if public.current_user_role() = 'admin' then
    null; -- admin her zaman yetkili
  elsif public.current_user_role() = 'mudur' and public.current_user_department() = v_request.department_id then
    null; -- talebin GÜNCEL biriminin müdürü yetkili
  else
    raise exception 'Bu talebi yönlendirme yetkiniz yok.';
  end if;

  select * into v_target_department from public.departments where id = p_new_department_id;
  if not found then
    raise exception 'Hedef birim bulunamadı.';
  end if;
  if not v_target_department.is_active then
    raise exception 'Hedef birim pasif, talep yönlendirilemez.';
  end if;
  if p_new_department_id = v_request.department_id then
    raise exception 'Talep zaten bu birimde.';
  end if;

  -- assigned_to NULL'a çekiliyor: eski birimin atanan personeli,
  -- "personel_atanan_talepleri_gorebilir" RLS kuralı department eşleşmesi
  -- ARAMADIĞI için (sadece assigned_to = kendisi kontrol ediyor) stale bir
  -- assigned_to ile talebi görmeye devam ederdi. Yeni birimin müdürü zaten
  -- yeniden atama yapması gerektiği için bu doğal/beklenen bir sıfırlama.
  update public.requests
  set department_id = p_new_department_id, assigned_to = null
  where id = p_request_id;

  insert into public.request_department_reassignments
    (request_id, old_department_id, new_department_id, reassigned_by)
  values (p_request_id, v_request.department_id, p_new_department_id, auth.uid());
end;
$$;


ALTER FUNCTION "public"."reassign_request_department"("p_request_id" "uuid", "p_new_department_id" bigint) OWNER TO "postgres";


GRANT ALL ON FUNCTION "public"."reassign_request_department"("p_request_id" "uuid", "p_new_department_id" bigint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."reassign_request_department"("p_request_id" "uuid", "p_new_department_id" bigint) TO "service_role";


--
-- Faz 5 (2026-07-21) — SLA + istatistikler: çözüm süresi takibi.
--
-- requests.resolved_at: rapor onaylandığında (results.approval_status =
-- 'onaylandi') dolar; talep detayında "X saat/gün içinde çözüldü" göstermek
-- için kullanılır. requests.sla_notified_at: check_sla_breaches() RPC'sinin
-- aynı talep için birden fazla eskalasyon bildirimi üretmesini önler.
--
ALTER TABLE "public"."requests"
    ADD COLUMN IF NOT EXISTS "resolved_at" timestamp with time zone,
    ADD COLUMN IF NOT EXISTS "sla_notified_at" timestamp with time zone;


-- sync_request_status_from_result()'ın yeniden tanımı (orijinali satır
-- 276'da, dosyanın geri kalanındaki Faz 1/Faz 4 desenine uygun olarak burada
-- DOKUNULMADAN bırakıldı — bu proje migration dosyasını append-only
-- kronolojik bir günlük olarak tutuyor, en son CREATE OR REPLACE kazanır).
-- Tek fark: resolved_at artık onay/onay-geri-alma durumuna göre set/temizleniyor.
--
-- ÖNEMLİ: old.approval_status, INSERT olaylarında (TG_OP='INSERT') OLD kaydı
-- hiç atanmamış olduğu için doğrudan bir SQL CASE içinde referans
-- verilemez ("record "old" is not assigned yet" hatası verir) — bu yüzden
-- resolved_at'ı temizleme kararı, SQL'e geçmeden ÖNCE ayrı bir PL/pgSQL IF
-- ile (TG_OP kontrolü short-circuit garantili) bir boolean değişkende
-- hesaplanıyor.
CREATE OR REPLACE FUNCTION "public"."sync_request_status_from_result"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_created_by uuid;
  v_clear_resolved_at boolean := false;
begin
  -- Faz 4'te RLS'in müdürün onay durumunu 'onaylandi'dan geri çevirmesini
  -- engellemediği bulundu (UI hiç yapmıyor ama DB izin veriyor) — bu yüzden
  -- resolved_at, savunma amaçlı, onay geri alınırsa temizleniyor.
  if TG_OP = 'UPDATE' and old.approval_status = 'onaylandi' and new.approval_status <> 'onaylandi' then
    v_clear_resolved_at := true;
  end if;

  update requests
  set status = case new.approval_status
    when 'beklemede' then 'cozuldu'
    when 'onaylandi' then 'onaylandi'
    when 'reddedildi' then 'reddedildi'
    else status
  end,
  resolved_at = case
    when new.approval_status = 'onaylandi' then now()
    when v_clear_resolved_at then null
    else resolved_at
  end
  where id = new.request_id
  returning created_by into v_created_by;

  if new.approval_status = 'onaylandi' and v_created_by is not null then
    insert into notifications (user_id, request_id, message)
    values (v_created_by, new.request_id, 'Talebiniz onaylandı, sonuçlandı.');
  elsif new.approval_status = 'reddedildi' then
    insert into notifications (user_id, request_id, message)
    values (new.resolved_by, new.request_id, 'Raporunuz reddedildi, lütfen yeniden inceleyin.');
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."sync_request_status_from_result"() OWNER TO "postgres";


--
-- Faz 5 (2026-07-21) — SLA eskalasyonu: check_sla_breaches() RPC.
--
-- Kullanıcı kararı: DB tarafı zamanlanmış kontrol (pg_cron) YERİNE uygulama
-- açılışında kontrol — pg_cron bu self-hosted kurulumda etkin değil,
-- etkinleştirmek shared_preload_libraries + container yeniden yapılandırması
-- gerektirir (Faz 2'deki Inbucket'a benzer bir altyapı riski). Bu RPC,
-- müdür/admin home_screen.dart'ı her açtığında fire-and-forget çağrılır.
--
-- Eşik: sabit 3 gün (kullanıcı kararı — ayrı bir ayar tablosu YOK).
-- Tekrar hatırlatma: YOK — sla_notified_at set edildikten sonra o talep için
-- bir daha bildirim üretilmez (kullanıcı kararı, tek seferlik uyarı).
-- Müdürsüz birim: admin(ler)e bildirilir (kullanıcı kararı). sla_notified_at
-- SADECE gerçekten en az bir bildirim eklendiyse set edilir — aksi halde
-- müdürsüz bir birimdeki talep hiç bildirim gitmeden "işlendi" gibi görünüp
-- bir daha asla kontrol edilmezdi (plan aşamasında bulunan bir hata).
--

CREATE OR REPLACE FUNCTION "public"."check_sla_breaches"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_request record;
  v_notified_count int;
  v_message text;
  v_days_open int;
begin
  if not public.current_user_is_active() then
    raise exception 'Hesabınız pasifleştirilmiş, bu işlemi yapamazsınız.';
  end if;

  for v_request in
    select id, title, department_id, created_at
    from public.requests
    where status in ('acik', 'cozuldu')
      and created_at < now() - interval '3 days'
      and sla_notified_at is null
  loop
    v_days_open := extract(day from now() - v_request.created_at);
    v_message := format('"%s" başlıklı talep %s gündür açık, kontrol edin.', v_request.title, v_days_open);

    insert into public.notifications (user_id, request_id, message)
    select u.id, v_request.id, v_message
    from public.users u
    where u.department_id = v_request.department_id
      and u.role = 'mudur'
      and u.is_active;

    get diagnostics v_notified_count = row_count;

    -- Departmanda aktif müdür yoksa admin(ler)e bildirilir (kullanıcı kararı)
    -- — müdürsüz bir birim zaten başlı başına operasyonel bir sorun.
    if v_notified_count = 0 then
      insert into public.notifications (user_id, request_id, message)
      select u.id, v_request.id, v_message || ' (Birimde aktif müdür bulunamadı.)'
      from public.users u
      where u.role = 'admin'
        and u.is_active;

      get diagnostics v_notified_count = row_count;
    end if;

    if v_notified_count > 0 then
      update public.requests set sla_notified_at = now() where id = v_request.id;
    end if;
  end loop;
end;
$$;


ALTER FUNCTION "public"."check_sla_breaches"() OWNER TO "postgres";


GRANT ALL ON FUNCTION "public"."check_sla_breaches"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_sla_breaches"() TO "service_role";


--
-- Faz 5 (2026-07-21) — İstatistikler: get_admin_stats() / get_manager_stats().
--
-- İki ayrı RPC (tek RPC + role'e göre farklı dönüş şekli YERİNE) — bu kod
-- tabanının hiçbir RPC'si dönüş şeklini caller role'üne göre değiştirmiyor
-- (reassign_request_department role'e göre sadece YETKİ kontrolü yapıyor,
-- hep aynı şeyi döndürüyor); rol dallanmasını Dart tarafına sızdırmamak için
-- ayrı RPC tercih edildi. RETURNS TABLE kullanılıyor (jsonb değil) — veri
-- zaten tablosal, Flutter tarafı List<Map<String,dynamic>>.from(response) ile
-- diğer ekranlardaki desenle aynı şekilde tüketebiliyor.
--
-- avg_resolution_hours: resolved_at sadece 'onaylandi' durumundaki taleplerde
-- dolu olduğu için (bkz. sync_request_status_from_result()), avg() diğer
-- durumlardaki NULL resolved_at'ları zaten otomatik yok sayıyor — ayrı bir
-- FILTER koşuluna gerek yok.
--

CREATE OR REPLACE FUNCTION "public"."get_admin_stats"() RETURNS TABLE(
    "department_id" bigint,
    "department_name" "text",
    "status" "text",
    "request_count" bigint,
    "avg_resolution_hours" numeric
)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if not public.current_user_is_active() then
    raise exception 'Hesabınız pasifleştirilmiş, bu işlemi yapamazsınız.';
  end if;
  if public.current_user_role() <> 'admin' then
    raise exception 'Bu işlem için admin yetkisi gerekir.';
  end if;

  return query
  select r.department_id, d.name, r.status, count(*)::bigint,
    avg(extract(epoch from (r.resolved_at - r.created_at)) / 3600.0)
  from public.requests r
  join public.departments d on d.id = r.department_id
  group by r.department_id, d.name, r.status
  order by d.name, r.status;
end;
$$;


ALTER FUNCTION "public"."get_admin_stats"() OWNER TO "postgres";


GRANT ALL ON FUNCTION "public"."get_admin_stats"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_admin_stats"() TO "service_role";


CREATE OR REPLACE FUNCTION "public"."get_manager_stats"() RETURNS TABLE(
    "status" "text",
    "request_count" bigint,
    "avg_resolution_hours" numeric
)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if not public.current_user_is_active() then
    raise exception 'Hesabınız pasifleştirilmiş, bu işlemi yapamazsınız.';
  end if;
  if public.current_user_role() <> 'mudur' then
    raise exception 'Bu işlem için müdür yetkisi gerekir.';
  end if;

  return query
  select r.status, count(*)::bigint,
    avg(extract(epoch from (r.resolved_at - r.created_at)) / 3600.0)
  from public.requests r
  where r.department_id = public.current_user_department()
  group by r.status
  order by r.status;
end;
$$;


ALTER FUNCTION "public"."get_manager_stats"() OWNER TO "postgres";


GRANT ALL ON FUNCTION "public"."get_manager_stats"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_manager_stats"() TO "service_role";


-- Faz 5 devamı (2026-07-22) — İstatistik dashboard'u için çözüm süresi
-- trendi: get_admin_resolution_trend() / get_manager_resolution_trend().
--
-- get_admin_stats()/get_manager_stats() ile AYNI desen: tek RPC + role'e
-- göre farklı dönüş şekli YERİNE iki ayrı RPC (rol dallanmasını Dart
-- tarafına sızdırmamak için, bkz. yukarıdaki gerekçe).
--
-- Aylık kırılım (date_trunc('month', ...)) seçildi — haftalık kırılım şu an
-- mevcut az sayıda test verisiyle anlamlı bir trend göstermezdi.
-- resolved_at'ı NULL olan (henüz onaylanmamış VEYA CLAUDE.md'nin bilinen
-- sınırlaması gereği geçmişe dönük doldurulmamış) kayıtlar `where
-- r.resolved_at is not null` ile hariç tutuluyor — bu satırlar
-- date_trunc(NULL) = NULL olacağından zaten kendi (anlamsız) grubunu
-- oluştururdu, açıkça filtrelemek daha doğru.

CREATE OR REPLACE FUNCTION "public"."get_admin_resolution_trend"() RETURNS TABLE(
    "period_start" "date",
    "avg_resolution_hours" numeric,
    "request_count" bigint
)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if not public.current_user_is_active() then
    raise exception 'Hesabınız pasifleştirilmiş, bu işlemi yapamazsınız.';
  end if;
  if public.current_user_role() <> 'admin' then
    raise exception 'Bu işlem için admin yetkisi gerekir.';
  end if;

  return query
  select date_trunc('month', r.resolved_at)::date,
    avg(extract(epoch from (r.resolved_at - r.created_at)) / 3600.0),
    count(*)::bigint
  from public.requests r
  where r.resolved_at is not null
  group by date_trunc('month', r.resolved_at)
  order by 1;
end;
$$;


ALTER FUNCTION "public"."get_admin_resolution_trend"() OWNER TO "postgres";


GRANT ALL ON FUNCTION "public"."get_admin_resolution_trend"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_admin_resolution_trend"() TO "service_role";


CREATE OR REPLACE FUNCTION "public"."get_manager_resolution_trend"() RETURNS TABLE(
    "period_start" "date",
    "avg_resolution_hours" numeric,
    "request_count" bigint
)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if not public.current_user_is_active() then
    raise exception 'Hesabınız pasifleştirilmiş, bu işlemi yapamazsınız.';
  end if;
  if public.current_user_role() <> 'mudur' then
    raise exception 'Bu işlem için müdür yetkisi gerekir.';
  end if;

  return query
  select date_trunc('month', r.resolved_at)::date,
    avg(extract(epoch from (r.resolved_at - r.created_at)) / 3600.0),
    count(*)::bigint
  from public.requests r
  where r.resolved_at is not null
    and r.department_id = public.current_user_department()
  group by date_trunc('month', r.resolved_at)
  order by 1;
end;
$$;


ALTER FUNCTION "public"."get_manager_resolution_trend"() OWNER TO "postgres";


GRANT ALL ON FUNCTION "public"."get_manager_resolution_trend"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_manager_resolution_trend"() TO "service_role";


--
-- Görsel kimlik + profil genişletmesi (2026-07-22): profil fotoğrafı,
-- adminin onayıyla e-posta değişikliği. KVKK notuyla aynı ilkeyle bilinçli
-- bir kapsam kararı: e-posta değişikliği GoTrue'nun kendi "yeni adrese
-- doğrulama linki gönder" akışına HİÇ girmiyor (o akış SMTP + gerçek bir
-- production e-posta servisi ister) — bunun yerine kullanıcı yeni adresi
-- talep eder, admin elle inceleyip onaylar/reddeder; onaylanınca
-- auth.users.email + public.users.email DOĞRUDAN (postgres sahipliğiyle,
-- security definer fonksiyon içinde) güncellenir ve email_confirmed_at
-- admin onayının kendisi "doğrulama" sayıldığı için hemen doldurulur.
--

ALTER TABLE "public"."users" ADD COLUMN IF NOT EXISTS "avatar_url" "text";


COMMENT ON COLUMN "public"."users"."avatar_url" IS 'avatars bucket''indeki dosya yolu (örn. "{user_id}/avatar") — NULL ise baş harf rozeti gösterilir';


CREATE TABLE IF NOT EXISTS "public"."email_change_requests" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "current_email" "text" NOT NULL,
    "requested_email" "text" NOT NULL,
    "status" "text" DEFAULT 'beklemede'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "reviewed_by" "uuid",
    "reviewed_at" timestamp with time zone,
    CONSTRAINT "email_change_requests_status_check" CHECK (("status" = ANY (ARRAY['beklemede'::"text", 'onaylandi'::"text", 'reddedildi'::"text"])))
);


ALTER TABLE "public"."email_change_requests" OWNER TO "postgres";


COMMENT ON TABLE "public"."email_change_requests" IS 'personel/vatandaş/müdürün talep ettiği, adminin onayladığı/reddettiği e-posta değişiklik talepleri';


ALTER TABLE ONLY "public"."email_change_requests"
    ADD CONSTRAINT "email_change_requests_pkey" PRIMARY KEY ("id");


ALTER TABLE ONLY "public"."email_change_requests"
    ADD CONSTRAINT "email_change_requests_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;


ALTER TABLE ONLY "public"."email_change_requests"
    ADD CONSTRAINT "email_change_requests_reviewed_by_fkey" FOREIGN KEY ("reviewed_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;


ALTER TABLE "public"."email_change_requests" ENABLE ROW LEVEL SECURITY;


-- SELECT: kendi talepleri + admin hepsini görür. INSERT/UPDATE'e KASITLI
-- olarak hiçbir permissive politika yok — tabloya yazma tamamen
-- `request_email_change()`/`admin_review_email_change()` (security definer,
-- postgres sahipliğiyle RLS'i bypass ediyor) üzerinden yapılıyor; bu
-- fonksiyonlar "zaten bekleyen talep var mı", "e-posta başka birinde var mı"
-- gibi kontrolleri tek yerde (Dart tarafına sızdırmadan) uyguluyor.
CREATE POLICY "kendi_talebini_veya_admin_hepsini_gorebilir" ON "public"."email_change_requests" FOR SELECT USING ((("user_id" = "auth"."uid"()) OR ("public"."current_user_role"() = 'admin'::"text")));


CREATE POLICY "pasif_kullanici_sinirlamasi_select" ON "public"."email_change_requests" AS RESTRICTIVE FOR SELECT USING ("public"."current_user_is_active"());


GRANT ALL ON TABLE "public"."email_change_requests" TO "authenticated";
GRANT ALL ON TABLE "public"."email_change_requests" TO "service_role";


CREATE OR REPLACE FUNCTION "public"."request_email_change"("p_new_email" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_user_id uuid := auth.uid();
  v_current_email text;
  v_new_email text := lower(trim(p_new_email));
  v_new_id uuid;
begin
  if v_user_id is null then
    raise exception 'Oturum bulunamadı.';
  end if;
  if not public.current_user_is_active() then
    raise exception 'Hesabınız pasifleştirilmiş, bu işlemi yapamazsınız.';
  end if;
  if v_new_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Geçerli bir e-posta adresi girin.';
  end if;

  select email into v_current_email from public.users where id = v_user_id;
  if v_new_email = lower(v_current_email) then
    raise exception 'Yeni e-posta, mevcut e-postanızla aynı.';
  end if;

  if exists (
    select 1 from public.email_change_requests
    where user_id = v_user_id and status = 'beklemede'
  ) then
    raise exception 'Zaten onay bekleyen bir e-posta değişikliği talebiniz var.';
  end if;

  if exists (select 1 from auth.users where lower(email) = v_new_email) then
    raise exception 'Bu e-posta adresi başka bir hesap tarafından kullanılıyor.';
  end if;

  insert into public.email_change_requests (user_id, current_email, requested_email)
  values (v_user_id, v_current_email, v_new_email)
  returning id into v_new_id;

  return v_new_id;
end;
$$;


ALTER FUNCTION "public"."request_email_change"("p_new_email" "text") OWNER TO "postgres";


GRANT ALL ON FUNCTION "public"."request_email_change"("p_new_email" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."request_email_change"("p_new_email" "text") TO "service_role";


CREATE OR REPLACE FUNCTION "public"."admin_review_email_change"("p_request_id" "uuid", "p_approve" boolean) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_request record;
begin
  if not public.current_user_is_active() then
    raise exception 'Hesabınız pasifleştirilmiş, bu işlemi yapamazsınız.';
  end if;
  if public.current_user_role() <> 'admin' then
    raise exception 'Bu işlem için admin yetkisi gerekir.';
  end if;

  select * into v_request from public.email_change_requests
  where id = p_request_id and status = 'beklemede'
  for update;
  if not found then
    raise exception 'Talep bulunamadı veya zaten işleme alınmış.';
  end if;

  if p_approve then
    if exists (select 1 from auth.users where lower(email) = lower(v_request.requested_email) and id <> v_request.user_id) then
      raise exception 'Bu e-posta adresi başka bir hesap tarafından kullanılıyor.';
    end if;

    -- Doğrudan auth.users güncellemesi: bu proje service_role/Edge Function
    -- altyapısına sahip değil (bkz. CLAUDE.md, Faz 4 notu) — ama security
    -- definer fonksiyon postgres sahipliğiyle çalıştığı için auth şemasına
    -- doğrudan erişebiliyor (handle_new_user() trigger'ıyla aynı desen).
    -- email_confirmed_at admin onayının kendisini doğrulama saydığı için
    -- hemen dolduruluyor — GoTrue'nun kendi "yeni adrese link gönder"
    -- akışı burada BİLİNÇLİ olarak devre dışı.
    update auth.users set email = v_request.requested_email, email_confirmed_at = now()
    where id = v_request.user_id;

    update public.users set email = v_request.requested_email where id = v_request.user_id;

    update public.email_change_requests
    set status = 'onaylandi', reviewed_by = auth.uid(), reviewed_at = now()
    where id = p_request_id;
  else
    update public.email_change_requests
    set status = 'reddedildi', reviewed_by = auth.uid(), reviewed_at = now()
    where id = p_request_id;
  end if;
end;
$$;


ALTER FUNCTION "public"."admin_review_email_change"("p_request_id" "uuid", "p_approve" boolean) OWNER TO "postgres";


GRANT ALL ON FUNCTION "public"."admin_review_email_change"("p_request_id" "uuid", "p_approve" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_review_email_change"("p_request_id" "uuid", "p_approve" boolean) TO "service_role";


--
-- Storage: avatars bucket'ı (private) + storage.objects RLS. Yol kuralı:
-- "{user_id}/avatar" (uzantısız, sabit ad) — her yeniden yüklemede aynı
-- yolun üzerine yazılır (`upsert: true`), böylece eski dosya/format
-- değişse de tek bir dosya kalır ve `users.avatar_url` her zaman aynı yolu
-- gösterir.
--

INSERT INTO "storage"."buckets" ("id", "name", "public", "file_size_limit", "allowed_mime_types")
VALUES (
  'avatars',
  'avatars',
  false,
  5242880,
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT ("id") DO NOTHING;


CREATE POLICY "kendi_avatarini_veya_admin_hepsini_gorebilir" ON "storage"."objects" FOR SELECT USING ((("bucket_id" = 'avatars'::"text") AND ((("storage"."foldername"("name"))[1] = ("auth"."uid"())::"text") OR ("public"."current_user_role"() = 'admin'::"text"))));


CREATE POLICY "kendi_avatarini_yukleyebilir" ON "storage"."objects" FOR INSERT WITH CHECK ((("bucket_id" = 'avatars'::"text") AND (("storage"."foldername"("name"))[1] = ("auth"."uid"())::"text")));


CREATE POLICY "kendi_avatarini_guncelleyebilir" ON "storage"."objects" FOR UPDATE USING ((("bucket_id" = 'avatars'::"text") AND (("storage"."foldername"("name"))[1] = ("auth"."uid"())::"text")));


CREATE POLICY "kendi_avatarini_silebilir" ON "storage"."objects" FOR DELETE USING ((("bucket_id" = 'avatars'::"text") AND (("storage"."foldername"("name"))[1] = ("auth"."uid"())::"text")));


--
-- Faz 6 (2026-07-23) — Puanlama, talebi yeniden açma, talep geçmişi.
--
-- Kullanıcıyla netleşen kararlar: (1) yeniden açma yetkisi sadece talebi
-- açan kişi + admin'de (müdür yok); (2) yeniden açılan talep atanmamış
-- duruma döner, müdür yeniden atar; (3) puanlama sadece giriş yapmış talep
-- sahibi için (anonim talepler kapsam dışı — hesapsız oldukları için
-- kimlik doğrulaması/tekrar puanlama engeli yok); (4) ortalama puan hem
-- personelin kendi profilinde hem müdürün "Ata" ekranında hem admin'in
-- Kullanıcı Yönetimi'nde hem admin dashboard'unda birim bazlı grafikte
-- gösterilecek.
--
-- Mimari kararlar:
-- - `results.request_id` UNIQUE olduğu için (bkz. tablo tanımı) bir talep
--   aynı anda sadece TEK aktif rapora sahip olabiliyor; yeniden açma bu
--   satırı SİLİYOR (önce request_history'ye rapor metni + o anki personel
--   ADI anlık görüntü olarak yazılıyor, sonra silme yapılıyor) — böylece
--   personel yeniden "Çözümle" ile SIFIRDAN rapor girebiliyor (INSERT'i
--   engelleyen UNIQUE ihlali oluşmuyor).
-- - `request_ratings.request_id` da UNIQUE — bir talep için her zaman TEK
--   aktif puan tutulur; talep yeniden açılıp tekrar onaylanırsa açan kişi
--   yeniden puanlayabilir (upsert), bu ESKİ puanın (ve eski personelin buna
--   katkısının) üzerine yazar. Bilinçli bir basitleştirme: geçmiş
--   döngülerin puanı ayrı ayrı SAKLANMIYOR, sadece EN GÜNCEL puan sayılıyor
--   (Trendyol tarzı ortalamalar `avg(rating) group by personnel_id` ile CANLI
--   hesaplanıyor, ayrı bir "ortalama" sütunu hiçbir yerde TUTULMUYOR).
-- - `request_history`: personel/müdür/admin ekranlarında gösterilecek genel
--   zaman çizelgesi. GİZLİLİK KARARI: `acan_kisi_kendi_talebini_gorebilir`
--   RLS deseninde olduğu gibi, personel/müdür bir VATANDAŞIN `users`
--   satırını göremiyor (sadece admin görebiliyor) — bu yüzden vatandaş/
--   anonim aksiyonlarının (created/reopened/rated) `actor_label`'ı YAZMA
--   ANINDA sabit bir Türkçe etiketle ("Talebi açan kişi") dolduruluyor,
--   personel işlemlerinde (assigned/resolved/approved/rejected/
--   department_changed) ise gerçek ad YAZMA ANINDA (security definer
--   fonksiyon/trigger içinde, RLS'i bypass ederek) `users` tablosundan OKUNUP
--   metne GÖMÜLÜYOR. Böylece Flutter tarafı OKUMA anında `users` tablosuna
--   hiç join YAPMIYOR — hem RLS sızıntısı riski hem "kullanıcı silinmiş/adı
--   değişmiş" tutarsızlığı olmuyor (tarihsel an itibariyle doğru kalıyor).
--

--
-- request_ratings — açan kişinin, onaylanmış bir talebi 5 yıldız üzerinden
-- değerlendirmesi. personnel_id, puanlama ANINDA results.resolved_by'dan
-- ANLIK GÖRÜNTÜ olarak alınır (results satırı ileride silinse/değişse bile
-- kimin puanlandığı sabit kalsın diye).
--
CREATE TABLE IF NOT EXISTS "public"."request_ratings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "request_id" "uuid" NOT NULL,
    "personnel_id" "uuid" NOT NULL,
    "rated_by" "uuid" NOT NULL,
    "rating" smallint NOT NULL,
    "comment" "text",
    CONSTRAINT "request_ratings_rating_check" CHECK ((("rating" >= 1) AND ("rating" <= 5)))
);


ALTER TABLE "public"."request_ratings" OWNER TO "postgres";


COMMENT ON TABLE "public"."request_ratings" IS 'açan kişinin onaylanmış talebe verdiği 1-5 yıldız puan; personel ortalama puanı bu tablodan canlı hesaplanır';


ALTER TABLE ONLY "public"."request_ratings"
    ADD CONSTRAINT "request_ratings_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."request_ratings"
    ADD CONSTRAINT "request_ratings_request_id_key" UNIQUE ("request_id");

ALTER TABLE ONLY "public"."request_ratings"
    ADD CONSTRAINT "request_ratings_request_id_fkey" FOREIGN KEY ("request_id") REFERENCES "public"."requests"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."request_ratings"
    ADD CONSTRAINT "request_ratings_personnel_id_fkey" FOREIGN KEY ("personnel_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."request_ratings"
    ADD CONSTRAINT "request_ratings_rated_by_fkey" FOREIGN KEY ("rated_by") REFERENCES "public"."users"("id") ON DELETE CASCADE;

ALTER TABLE "public"."request_ratings" ENABLE ROW LEVEL SECURITY;

-- Puanlayan kendi verdiği puanı, puanlanan personel kendi hakkındaki
-- puanları, müdür kendi biriminin personeli hakkındaki puanları, admin
-- hepsini görebilir. INSERT/UPDATE için BİLİNÇLİ olarak hiçbir politika YOK
-- — tek yazma yolu aşağıdaki `rate_request()` (security definer) RPC'si.
CREATE POLICY "puan_gorebilenler" ON "public"."request_ratings" FOR SELECT TO "authenticated" USING ((
    ("rated_by" = "auth"."uid"())
    OR ("personnel_id" = "auth"."uid"())
    OR ("public"."current_user_role"() = 'admin'::"text")
    OR (("public"."current_user_role"() = 'mudur'::"text") AND (EXISTS ( SELECT 1 FROM "public"."users" "u" WHERE (("u"."id" = "request_ratings"."personnel_id") AND ("u"."department_id" = "public"."current_user_department"())))))
));

CREATE POLICY "pasif_kullanici_sinirlamasi_select" ON "public"."request_ratings" AS RESTRICTIVE FOR SELECT TO "authenticated" USING ((("rated_by" = "auth"."uid"()) OR ("personnel_id" = "auth"."uid"()) OR "public"."current_user_is_active"()));


--
-- request_history — personel/müdür/admin ekranlarında gösterilen, bir
-- talebin başından beri geçirdiği tüm aşamaların salt-okunur günlüğü.
-- Yazma yolu YOK (hiçbir INSERT/UPDATE/DELETE politikası tanımlanmadı) —
-- sadece aşağıdaki trigger'lar/RPC'ler (security definer, tablo sahibi
-- postgres) satır ekleyebiliyor.
--
CREATE TABLE IF NOT EXISTS "public"."request_history" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "request_id" "uuid" NOT NULL,
    "event_type" "text" NOT NULL,
    "actor_id" "uuid",
    "actor_label" "text" NOT NULL,
    "detail" "jsonb",
    CONSTRAINT "request_history_event_type_check" CHECK (("event_type" = ANY (ARRAY['created'::"text", 'assigned'::"text", 'department_changed'::"text", 'resolved'::"text", 'report_resubmitted'::"text", 'approved'::"text", 'rejected'::"text", 'reopened'::"text", 'rated'::"text"])))
);


ALTER TABLE "public"."request_history" OWNER TO "postgres";


COMMENT ON TABLE "public"."request_history" IS 'bir talebin zaman çizelgesi (oluşturma/atama/çözüm/onay/red/yeniden açma/puanlama) — sadece personel/müdür/admin ekranlarında gösterilir';


ALTER TABLE ONLY "public"."request_history"
    ADD CONSTRAINT "request_history_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."request_history"
    ADD CONSTRAINT "request_history_request_id_fkey" FOREIGN KEY ("request_id") REFERENCES "public"."requests"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."request_history"
    ADD CONSTRAINT "request_history_actor_id_fkey" FOREIGN KEY ("actor_id") REFERENCES "public"."users"("id") ON DELETE SET NULL;

ALTER TABLE "public"."request_history" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "gorebilen_calisanlar_gecmisi_gorebilir" ON "public"."request_history" FOR SELECT TO "authenticated" USING ((
    ("public"."current_user_role"() = ANY (ARRAY['personel'::"text", 'mudur'::"text", 'admin'::"text"]))
    AND (EXISTS ( SELECT 1 FROM "public"."requests" "r" WHERE (("r"."id" = "request_history"."request_id") AND (
        ("r"."assigned_to" = "auth"."uid"())
        OR (("public"."current_user_role"() = 'mudur'::"text") AND (NOT ("r"."department_id" IS DISTINCT FROM "public"."current_user_department"())))
        OR ("public"."current_user_role"() = 'admin'::"text")
    ))))
));

CREATE POLICY "pasif_kullanici_sinirlamasi_select" ON "public"."request_history" AS RESTRICTIVE FOR SELECT TO "authenticated" USING ("public"."current_user_is_active"());


--
-- requests.reopened_count — kaç kez yeniden açıldığını gösteren basit bir
-- sayaç (previously_rejected'daki boolean deseninin sayaç versiyonu);
-- request_detail_screen.dart'ta "Bu talep daha önce N kez yeniden açılmıştı"
-- rozeti için kullanılıyor.
--
ALTER TABLE "public"."requests"
    ADD COLUMN IF NOT EXISTS "reopened_count" integer DEFAULT 0 NOT NULL;


--
-- log_request_created() — bir talep oluşturulduğunda request_history'ye
-- 'created' olayını ekler. actor_label gizlilik kuralına uyar (bkz. yukarı):
-- vatandaş/anonim için sabit etiket, personelin kendi açtığı talepte gerçek
-- ad (personel zaten meslektaşlarına görünür bir kimlik).
--
CREATE OR REPLACE FUNCTION "public"."log_request_created"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_actor_label text;
begin
  v_actor_label := case
    when new.created_by is null then 'Anonim'
    when new.requester_type = 'personel' then coalesce((select full_name from public.users where id = new.created_by), 'Personel')
    else 'Talebi açan kişi'
  end;

  insert into public.request_history (request_id, event_type, actor_id, actor_label, detail)
  values (new.id, 'created', new.created_by, v_actor_label, jsonb_build_object('title', new.title));

  return new;
end;
$$;


ALTER FUNCTION "public"."log_request_created"() OWNER TO "postgres";


CREATE OR REPLACE TRIGGER "log_request_created_after_insert" AFTER INSERT ON "public"."requests" FOR EACH ROW EXECUTE FUNCTION "public"."log_request_created"();


--
-- log_request_assigned() — müdürün bir talebi bir personele ATANMASINI
-- (assigned_to null'dan bir değere veya bir değerden başka bir değere
-- değiştiğinde) 'assigned' olayı olarak kaydeder. `reassign_request_department`
-- RPC'sinin assigned_to'yu NULL'a sıfırlamasında (yeni_deger IS NULL)
-- bilinçli olarak TETİKLENMEZ — o durum ayrıca 'department_changed' olarak
-- kaydediliyor.
--
CREATE OR REPLACE FUNCTION "public"."log_request_assigned"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_actor_label text;
  v_personnel_name text;
begin
  if new.assigned_to is distinct from old.assigned_to and new.assigned_to is not null then
    v_actor_label := coalesce((select full_name from public.users where id = auth.uid()), 'Müdür');
    v_personnel_name := coalesce((select full_name from public.users where id = new.assigned_to), 'Personel');

    insert into public.request_history (request_id, event_type, actor_id, actor_label, detail)
    values (new.id, 'assigned', auth.uid(), v_actor_label, jsonb_build_object('personnel_id', new.assigned_to, 'personnel_name', v_personnel_name));
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."log_request_assigned"() OWNER TO "postgres";


CREATE OR REPLACE TRIGGER "log_request_assigned_after_update" AFTER UPDATE OF "assigned_to" ON "public"."requests" FOR EACH ROW EXECUTE FUNCTION "public"."log_request_assigned"();


--
-- log_result_resolved() — personelin İLK raporu gönderdiği an ('resolved').
-- Sonraki düzenlemeler/yeniden gönderimler aşağıdaki log_result_updated()
-- tarafından 'report_resubmitted' olarak ayrıca kaydedilir.
--
CREATE OR REPLACE FUNCTION "public"."log_result_resolved"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_actor_label text;
begin
  v_actor_label := coalesce((select full_name from public.users where id = new.resolved_by), 'Personel');

  insert into public.request_history (request_id, event_type, actor_id, actor_label, detail)
  values (new.request_id, 'resolved', new.resolved_by, v_actor_label, jsonb_build_object('report_text', new.report_text));

  return new;
end;
$$;


ALTER FUNCTION "public"."log_result_resolved"() OWNER TO "postgres";


CREATE OR REPLACE TRIGGER "log_result_resolved_after_insert" AFTER INSERT ON "public"."results" FOR EACH ROW EXECUTE FUNCTION "public"."log_result_resolved"();


--
-- log_result_updated() — raporun onay durumu değiştiğinde ('approved'/
-- 'rejected') veya rapor metni değiştiğinde ('report_resubmitted', hem
-- redden sonra yeniden gönderimi hem onay beklerken düzenlemeyi kapsar)
-- ayrı ayrı olaylar ekler. İkisi de AYNI UPDATE'te değişebileceği için
-- (ör. red sonrası düzenleme approval_status'u da beklemede'ye çeker)
-- bağımsız `if`ler kullanılıyor (elsif DEĞİL) — biri diğerini engellemesin.
--
CREATE OR REPLACE FUNCTION "public"."log_result_updated"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_actor_label text;
begin
  if new.approval_status = 'onaylandi' and old.approval_status is distinct from 'onaylandi' then
    v_actor_label := coalesce((select full_name from public.users where id = new.approved_by), 'Müdür');
    insert into public.request_history (request_id, event_type, actor_id, actor_label, detail)
    values (new.request_id, 'approved', new.approved_by, v_actor_label, null);
  end if;

  if new.approval_status = 'reddedildi' and old.approval_status is distinct from 'reddedildi' then
    v_actor_label := coalesce((select full_name from public.users where id = new.approved_by), 'Müdür');
    insert into public.request_history (request_id, event_type, actor_id, actor_label, detail)
    values (new.request_id, 'rejected', new.approved_by, v_actor_label, null);
  end if;

  if new.report_text is distinct from old.report_text then
    v_actor_label := coalesce((select full_name from public.users where id = new.resolved_by), 'Personel');
    insert into public.request_history (request_id, event_type, actor_id, actor_label, detail)
    values (new.request_id, 'report_resubmitted', new.resolved_by, v_actor_label, jsonb_build_object('report_text', new.report_text));
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."log_result_updated"() OWNER TO "postgres";


CREATE OR REPLACE TRIGGER "log_result_updated_after_update" AFTER UPDATE ON "public"."results" FOR EACH ROW EXECUTE FUNCTION "public"."log_result_updated"();


--
-- reopen_request() — onaylanmış (sonuçlandırılmış) bir talebi açan kişi
-- veya admin yeniden açabilir ("sonradan tekrar sorun çıkabilir" senaryosu).
-- Kullanıcı kararı: sadece açan kişi + admin (müdür YOK); atama sıfırlanır,
-- müdür yeniden atar. Mevcut rapor, silinmeden ÖNCE request_history'ye
-- anlık görüntü olarak yazılır (bkz. dosya başındaki mimari not).
--
CREATE OR REPLACE FUNCTION "public"."reopen_request"("p_request_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_request record;
  v_result record;
  v_actor_label text;
  v_notified_count int;
begin
  if not public.current_user_is_active() then
    raise exception 'Hesabınız pasifleştirilmiş, bu işlemi yapamazsınız.';
  end if;

  select * into v_request from public.requests where id = p_request_id for update;
  if not found then
    raise exception 'Talep bulunamadı.';
  end if;

  if v_request.status <> 'onaylandi' then
    raise exception 'Sadece onaylanmış (sonuçlandırılmış) talepler yeniden açılabilir.';
  end if;

  if not ((v_request.created_by = auth.uid()) or (public.current_user_role() = 'admin')) then
    raise exception 'Bu talebi yeniden açma yetkiniz yok.';
  end if;

  select * into v_result from public.results where request_id = p_request_id;

  v_actor_label := case
    when public.current_user_role() = 'admin' then coalesce((select full_name from public.users where id = auth.uid()), 'Admin')
    else 'Talebi açan kişi'
  end;

  insert into public.request_history (request_id, event_type, actor_id, actor_label, detail)
  values (
    p_request_id, 'reopened', auth.uid(), v_actor_label,
    case when v_result is null then null else jsonb_build_object(
      'previous_report_text', v_result.report_text,
      'previous_personnel_name', (select full_name from public.users where id = v_result.resolved_by)
    ) end
  );

  delete from public.results where request_id = p_request_id;

  update public.requests
  set status = 'acik',
      assigned_to = null,
      resolved_at = null,
      sla_notified_at = null,
      reopened_count = reopened_count + 1
  where id = p_request_id;

  insert into public.notifications (user_id, request_id, message)
  select u.id, p_request_id, format('"%s" başlıklı talep, açan kişi tarafından yeniden açıldı.', v_request.title)
  from public.users u
  where u.department_id = v_request.department_id and u.role = 'mudur' and u.is_active;

  get diagnostics v_notified_count = row_count;

  if v_notified_count = 0 then
    insert into public.notifications (user_id, request_id, message)
    select u.id, p_request_id, format('"%s" başlıklı talep yeniden açıldı. (Birimde aktif müdür bulunamadı.)', v_request.title)
    from public.users u
    where u.role = 'admin' and u.is_active;
  end if;
end;
$$;


ALTER FUNCTION "public"."reopen_request"("p_request_id" "uuid") OWNER TO "postgres";


GRANT ALL ON FUNCTION "public"."reopen_request"("p_request_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."reopen_request"("p_request_id" "uuid") TO "service_role";


--
-- rate_request() — sadece talebin (giriş yapmış) açan kişisi, 'onaylandi'
-- durumundaki bir talebi 1-5 yıldız + opsiyonel yorum ile puanlar.
-- personnel_id, o anki results.resolved_by'dan ANLIK GÖRÜNTÜ alınır (bkz.
-- dosya başındaki mimari not). Upsert: aynı talep tekrar puanlanırsa
-- (ör. yeniden açılıp tekrar onaylandıktan sonra) ESKİ puanın üzerine yazar.
--
CREATE OR REPLACE FUNCTION "public"."rate_request"("p_request_id" "uuid", "p_rating" smallint, "p_comment" "text" DEFAULT NULL) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_request record;
  v_personnel_id uuid;
begin
  if not public.current_user_is_active() then
    raise exception 'Hesabınız pasifleştirilmiş, bu işlemi yapamazsınız.';
  end if;

  if p_rating < 1 or p_rating > 5 then
    raise exception 'Puan 1 ile 5 arasında olmalıdır.';
  end if;

  select * into v_request from public.requests where id = p_request_id;
  if not found then
    raise exception 'Talep bulunamadı.';
  end if;

  if v_request.created_by is distinct from auth.uid() then
    raise exception 'Sadece talebi açan kişi puanlayabilir.';
  end if;

  if v_request.status <> 'onaylandi' then
    raise exception 'Sadece onaylanmış (sonuçlandırılmış) talepler puanlanabilir.';
  end if;

  select resolved_by into v_personnel_id from public.results where request_id = p_request_id;
  if v_personnel_id is null then
    raise exception 'Bu talep için bir çözüm raporu bulunamadı.';
  end if;

  insert into public.request_ratings (request_id, personnel_id, rated_by, rating, comment, updated_at)
  values (p_request_id, v_personnel_id, auth.uid(), p_rating, p_comment, now())
  on conflict (request_id) do update
    set personnel_id = excluded.personnel_id,
        rating = excluded.rating,
        comment = excluded.comment,
        updated_at = now();

  insert into public.request_history (request_id, event_type, actor_id, actor_label, detail)
  values (p_request_id, 'rated', auth.uid(), 'Talebi açan kişi', jsonb_build_object('rating', p_rating, 'comment', p_comment));
end;
$$;


ALTER FUNCTION "public"."rate_request"("p_request_id" "uuid", "p_rating" smallint, "p_comment" "text") OWNER TO "postgres";


GRANT ALL ON FUNCTION "public"."rate_request"("p_request_id" "uuid", "p_rating" smallint, "p_comment" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."rate_request"("p_request_id" "uuid", "p_rating" smallint, "p_comment" "text") TO "service_role";


--
-- reassign_request_department()'ın yeniden tanımı (orijinali satır 1377'de,
-- dosyanın geri kalanındaki desene uygun olarak orijinal DOKUNULMADAN
-- bırakıldı — bu proje migration dosyasını append-only kronolojik bir günlük
-- olarak tutuyor, en son CREATE OR REPLACE kazanır). Tek fark: artık
-- request_history'ye 'department_changed' olayı da ekliyor.
--
CREATE OR REPLACE FUNCTION "public"."reassign_request_department"("p_request_id" "uuid", "p_new_department_id" bigint) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_request record;
  v_target_department record;
  v_old_department_name text;
  v_actor_label text;
begin
  if not public.current_user_is_active() then
    raise exception 'Hesabınız pasifleştirilmiş, bu işlemi yapamazsınız.';
  end if;

  select * into v_request from public.requests where id = p_request_id for update;
  if not found then
    raise exception 'Talep bulunamadı.';
  end if;

  if v_request.status <> 'acik' then
    raise exception 'Sadece açık durumdaki talepler başka birime yönlendirilebilir.';
  end if;

  if public.current_user_role() = 'admin' then
    null;
  elsif public.current_user_role() = 'mudur' and public.current_user_department() = v_request.department_id then
    null;
  else
    raise exception 'Bu talebi yönlendirme yetkiniz yok.';
  end if;

  select * into v_target_department from public.departments where id = p_new_department_id;
  if not found then
    raise exception 'Hedef birim bulunamadı.';
  end if;
  if not v_target_department.is_active then
    raise exception 'Hedef birim pasif, talep yönlendirilemez.';
  end if;
  if p_new_department_id = v_request.department_id then
    raise exception 'Talep zaten bu birimde.';
  end if;

  select name into v_old_department_name from public.departments where id = v_request.department_id;

  update public.requests
  set department_id = p_new_department_id, assigned_to = null
  where id = p_request_id;

  insert into public.request_department_reassignments
    (request_id, old_department_id, new_department_id, reassigned_by)
  values (p_request_id, v_request.department_id, p_new_department_id, auth.uid());

  v_actor_label := coalesce((select full_name from public.users where id = auth.uid()), 'Yetkili');
  insert into public.request_history (request_id, event_type, actor_id, actor_label, detail)
  values (
    p_request_id, 'department_changed', auth.uid(), v_actor_label,
    jsonb_build_object('old_department_name', v_old_department_name, 'new_department_name', v_target_department.name)
  );
end;
$$;


ALTER FUNCTION "public"."reassign_request_department"("p_request_id" "uuid", "p_new_department_id" bigint) OWNER TO "postgres";


--
-- get_personnel_ratings() — çağıranın rolüne göre görebileceği personelin
-- (kendi rolü personel ise sadece kendisi, müdürse kendi biriminin
-- personeli, admin ise TÜM personel) ortalama puanı + puan sayısı.
-- LEFT JOIN request_ratings — hiç puanı olmayan personel de (avg_rating
-- null, rating_count 0) listede görünsün diye (Ata ekranında/Kullanıcı
-- Yönetimi'nde "henüz puan yok" gösterebilmek için).
--
CREATE OR REPLACE FUNCTION "public"."get_personnel_ratings"() RETURNS TABLE(
    "personnel_id" "uuid",
    "department_id" bigint,
    "department_name" "text",
    "avg_rating" numeric,
    "rating_count" bigint
)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if not public.current_user_is_active() then
    raise exception 'Hesabınız pasifleştirilmiş, bu işlemi yapamazsınız.';
  end if;

  if public.current_user_role() = 'personel' then
    return query
    select u.id, u.department_id, d.name, avg(rr.rating), count(rr.*)::bigint
    from public.users u
    left join public.departments d on d.id = u.department_id
    left join public.request_ratings rr on rr.personnel_id = u.id
    where u.id = auth.uid()
    group by u.id, u.department_id, d.name;
  elsif public.current_user_role() = 'mudur' then
    return query
    select u.id, u.department_id, d.name, avg(rr.rating), count(rr.*)::bigint
    from public.users u
    left join public.departments d on d.id = u.department_id
    left join public.request_ratings rr on rr.personnel_id = u.id
    where u.role = 'personel' and u.department_id = public.current_user_department()
    group by u.id, u.department_id, d.name;
  elsif public.current_user_role() = 'admin' then
    return query
    select u.id, u.department_id, d.name, avg(rr.rating), count(rr.*)::bigint
    from public.users u
    left join public.departments d on d.id = u.department_id
    left join public.request_ratings rr on rr.personnel_id = u.id
    where u.role = 'personel'
    group by u.id, u.department_id, d.name;
  else
    raise exception 'Bu işlem için yetkiniz yok.';
  end if;
end;
$$;


ALTER FUNCTION "public"."get_personnel_ratings"() OWNER TO "postgres";


GRANT ALL ON FUNCTION "public"."get_personnel_ratings"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_personnel_ratings"() TO "service_role";


--
-- ============================================================================
-- Faz 7 (2026-07-23) — Kurum-içi DM (özel mesajlaşma): personel ↔ kendi birim
-- müdürü, müdür ↔ admin. Kararlar (kullanıcıyla `AskQuestion` ile netleşti):
-- personel SADECE kendi biriminin müdürüyle konuşabilir; müdür, birden fazla
-- admin varsa mesaj başlatırken hangi admin'le konuşacağını seçer (liste);
-- vatandaş DM kapsamı DIŞINDA. Etiketleme (bir talebi mesaja iliştirme) ve
-- beğeni (kalp ikonu, her iki taraf da açıp kapatabilir) de bu fazın parçası.
--
-- Tasarım notu: `users` tablosunun normal RLS'i ("kendi profili + müdür kendi
-- biriminin personeli + admin herkes") personelin müdürünü, müdürün
-- admin'leri GÖRMESİNE izin vermiyor (bu roller birbirinin "personeli" değil).
-- Bu yüzden kişi listesi (`get_dm_contacts`) ve konuşma listesi
-- (`get_my_dm_conversations`) `SECURITY DEFINER` — `get_personnel_ratings()`
-- ile AYNI gerekçe.
-- ============================================================================
--

--
-- dm_conversations — iki kullanıcı arasındaki TEK konuşma. Yinelenen
-- konuşma oluşmasın diye participant_a/participant_b HER ZAMAN sıralı
-- (participant_a < participant_b) tutulur — hem CHECK kısıtlamasıyla hem
-- aşağıdaki `get_or_create_dm_conversation()` RPC'sinin sıralama mantığıyla
-- çift güvenceli. Okundu takibi için katılımcı başına ayrı `last_read_at`
-- sütunu (mesaj başına okundu-bilgisi YOK, basit tutuluyor).
--
CREATE TABLE IF NOT EXISTS "public"."dm_conversations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_message_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "participant_a" "uuid" NOT NULL,
    "participant_b" "uuid" NOT NULL,
    "participant_a_last_read_at" timestamp with time zone,
    "participant_b_last_read_at" timestamp with time zone,
    CONSTRAINT "dm_conversations_ordered_check" CHECK (("participant_a" < "participant_b"))
);


ALTER TABLE "public"."dm_conversations" OWNER TO "postgres";


COMMENT ON TABLE "public"."dm_conversations" IS 'personel↔müdür / müdür↔admin arası 1:1 DM konuşması; katılımcılar her zaman participant_a < participant_b sıralı tutulur';


ALTER TABLE ONLY "public"."dm_conversations"
    ADD CONSTRAINT "dm_conversations_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."dm_conversations"
    ADD CONSTRAINT "dm_conversations_unique_pair" UNIQUE ("participant_a", "participant_b");

ALTER TABLE ONLY "public"."dm_conversations"
    ADD CONSTRAINT "dm_conversations_participant_a_fkey" FOREIGN KEY ("participant_a") REFERENCES "public"."users"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."dm_conversations"
    ADD CONSTRAINT "dm_conversations_participant_b_fkey" FOREIGN KEY ("participant_b") REFERENCES "public"."users"("id") ON DELETE CASCADE;

ALTER TABLE "public"."dm_conversations" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "katilimci_konusmasini_gorebilir" ON "public"."dm_conversations" FOR SELECT TO "authenticated" USING ((
    ("participant_a" = "auth"."uid"())
    OR ("participant_b" = "auth"."uid"())
    OR ("public"."current_user_role"() = 'admin'::"text")
));

CREATE POLICY "pasif_kullanici_sinirlamasi_select" ON "public"."dm_conversations" AS RESTRICTIVE FOR SELECT TO "authenticated" USING ((("participant_a" = "auth"."uid"()) OR ("participant_b" = "auth"."uid"()) OR "public"."current_user_is_active"()));

-- Yazma (yeni konuşma oluşturma) yolu BİLİNÇLİ olarak yok — tek yol aşağıdaki
-- `get_or_create_dm_conversation()` (security definer) RPC'si, çünkü hangi rol
-- kombinasyonunun konuşabileceği (personel↔kendi müdürü, müdür↔admin) sade bir
-- RLS `with check`'iyle ifade edilemeyecek kadar çapraz-tablo mantığı içeriyor.


--
-- dm_messages — bir konuşmadaki tek mesaj. `tagged_request_id` doluysa mesaj
-- balonunda altı çizili bir bağlantı olarak gösterilip tıklanınca talep
-- detayı açılır (2026-07-23 "index seçeneğiyle etiketleme" isteği).
--
CREATE TABLE IF NOT EXISTS "public"."dm_messages" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "conversation_id" "uuid" NOT NULL,
    "sender_id" "uuid",
    "body" "text" NOT NULL,
    "tagged_request_id" "uuid",
    CONSTRAINT "dm_messages_body_not_empty" CHECK (("length"(TRIM(BOTH FROM "body")) > 0))
);


ALTER TABLE "public"."dm_messages" OWNER TO "postgres";


COMMENT ON TABLE "public"."dm_messages" IS 'DM konuşmasındaki tek mesaj; tagged_request_id doluysa mesajda bir talebe tıklanabilir referans var';


ALTER TABLE ONLY "public"."dm_messages"
    ADD CONSTRAINT "dm_messages_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."dm_messages"
    ADD CONSTRAINT "dm_messages_conversation_id_fkey" FOREIGN KEY ("conversation_id") REFERENCES "public"."dm_conversations"("id") ON DELETE CASCADE;

-- sender_id ON DELETE SET NULL — personnel_invites.created_by/used_by ile AYNI
-- gerekçe: gönderen hesabı silinse bile mesaj geçmişi (ve karşı tarafın
-- okuduğu içerik) kaybolmasın.
ALTER TABLE ONLY "public"."dm_messages"
    ADD CONSTRAINT "dm_messages_sender_id_fkey" FOREIGN KEY ("sender_id") REFERENCES "public"."users"("id") ON DELETE SET NULL;

ALTER TABLE ONLY "public"."dm_messages"
    ADD CONSTRAINT "dm_messages_tagged_request_id_fkey" FOREIGN KEY ("tagged_request_id") REFERENCES "public"."requests"("id") ON DELETE SET NULL;

ALTER TABLE "public"."dm_messages" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "katilimci_mesajlari_gorebilir" ON "public"."dm_messages" FOR SELECT TO "authenticated" USING ((
    EXISTS ( SELECT 1 FROM "public"."dm_conversations" "c" WHERE (("c"."id" = "dm_messages"."conversation_id") AND (("c"."participant_a" = "auth"."uid"()) OR ("c"."participant_b" = "auth"."uid"()) OR ("public"."current_user_role"() = 'admin'::"text"))))
));

CREATE POLICY "pasif_kullanici_sinirlamasi_select" ON "public"."dm_messages" AS RESTRICTIVE FOR SELECT TO "authenticated" USING ((
    "public"."current_user_is_active"()
    OR (EXISTS ( SELECT 1 FROM "public"."dm_conversations" "c" WHERE (("c"."id" = "dm_messages"."conversation_id") AND (("c"."participant_a" = "auth"."uid"()) OR ("c"."participant_b" = "auth"."uid"())))))
));

-- Mesaj gönderme RLS ÜZERİNDEN yapılıyor (rate_request/reopen_request'in
-- aksine — burada tekil bir INSERT dışında cross-row mantık yok, RPC'ye gerek
-- yok): gönderen kendisi olmalı, aktif olmalı, ve konuşmanın katılımcısı
-- olmalı.
CREATE POLICY "katilimci_mesaj_gonderebilir" ON "public"."dm_messages" FOR INSERT TO "authenticated" WITH CHECK ((
    ("sender_id" = "auth"."uid"())
    AND "public"."current_user_is_active"()
    AND (EXISTS ( SELECT 1 FROM "public"."dm_conversations" "c" WHERE (("c"."id" = "dm_messages"."conversation_id") AND (("c"."participant_a" = "auth"."uid"()) OR ("c"."participant_b" = "auth"."uid"())))))
));


--
-- dm_message_likes — bir mesajı "beğenme" (kalp ikonu). Her iki taraf da
-- (sadece kendi göndermediği mesajlarla sınırlı olmadan) beğenip geri
-- alabilir (2026-07-23 kararı). (message_id, user_id) PK'sı = toggle
-- (INSERT = beğen, DELETE = beğeniyi kaldır), aynı kullanıcı bir mesajı
-- birden çok kez beğenemez.
--
CREATE TABLE IF NOT EXISTS "public"."dm_message_likes" (
    "message_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."dm_message_likes" OWNER TO "postgres";


COMMENT ON TABLE "public"."dm_message_likes" IS 'bir DM mesajını beğenen kullanıcılar (toggle); konuşmadaki her iki taraf da beğenebilir';


ALTER TABLE ONLY "public"."dm_message_likes"
    ADD CONSTRAINT "dm_message_likes_pkey" PRIMARY KEY ("message_id", "user_id");

ALTER TABLE ONLY "public"."dm_message_likes"
    ADD CONSTRAINT "dm_message_likes_message_id_fkey" FOREIGN KEY ("message_id") REFERENCES "public"."dm_messages"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."dm_message_likes"
    ADD CONSTRAINT "dm_message_likes_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;

ALTER TABLE "public"."dm_message_likes" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "katilimci_begenileri_gorebilir" ON "public"."dm_message_likes" FOR SELECT TO "authenticated" USING ((
    EXISTS ( SELECT 1 FROM ("public"."dm_messages" "m" JOIN "public"."dm_conversations" "c" ON (("c"."id" = "m"."conversation_id"))) WHERE (("m"."id" = "dm_message_likes"."message_id") AND (("c"."participant_a" = "auth"."uid"()) OR ("c"."participant_b" = "auth"."uid"()) OR ("public"."current_user_role"() = 'admin'::"text"))))
));

CREATE POLICY "katilimci_begenebilir" ON "public"."dm_message_likes" FOR INSERT TO "authenticated" WITH CHECK ((
    ("user_id" = "auth"."uid"())
    AND "public"."current_user_is_active"()
    AND (EXISTS ( SELECT 1 FROM ("public"."dm_messages" "m" JOIN "public"."dm_conversations" "c" ON (("c"."id" = "m"."conversation_id"))) WHERE (("m"."id" = "dm_message_likes"."message_id") AND (("c"."participant_a" = "auth"."uid"()) OR ("c"."participant_b" = "auth"."uid"())))))
));

CREATE POLICY "kendi_begenisini_kaldirabilir" ON "public"."dm_message_likes" FOR DELETE TO "authenticated" USING (("user_id" = "auth"."uid"()));


--
-- notifications.request_id artık DM bildirimleri için NULL olabilir; yeni
-- conversation_id sütunu, bildirime tıklanınca hangi DM ekranının
-- açılacağını belirtir (`notifications_screen.dart` her iki alanı da kontrol
-- edecek şekilde güncellendi).
--
ALTER TABLE "public"."notifications" ALTER COLUMN "request_id" DROP NOT NULL;

ALTER TABLE "public"."notifications" ADD COLUMN IF NOT EXISTS "conversation_id" "uuid";

ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_conversation_id_fkey" FOREIGN KEY ("conversation_id") REFERENCES "public"."dm_conversations"("id") ON DELETE CASCADE;


--
-- get_dm_contacts() — çağıranın rolüne göre "kiminle yeni konuşma
-- başlatabilir" listesini döndürür. Pasif (is_active=false) kullanıcılar
-- listeye hiç girmez.
--
CREATE OR REPLACE FUNCTION "public"."get_dm_contacts"() RETURNS TABLE("user_id" "uuid", "full_name" "text", "role" "text", "avatar_url" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_role text;
  v_dept bigint;
begin
  if auth.uid() is null then
    raise exception 'Giriş yapmanız gerekiyor.';
  end if;

  select u.role, u.department_id into v_role, v_dept from public.users u where u.id = auth.uid();

  if v_role = 'personel' then
    return query
      select u.id, u.full_name, u.role, u.avatar_url
      from public.users u
      where u.role = 'mudur' and u.is_active and (u.department_id is not distinct from v_dept)
      order by u.full_name;
  elsif v_role = 'mudur' then
    return query
      select u.id, u.full_name, u.role, u.avatar_url
      from public.users u
      where u.is_active and (
        (u.role = 'personel' and (u.department_id is not distinct from v_dept))
        or u.role = 'admin'
      )
      order by u.role, u.full_name;
  elsif v_role = 'admin' then
    return query
      select u.id, u.full_name, u.role, u.avatar_url
      from public.users u
      where u.role = 'mudur' and u.is_active
      order by u.full_name;
  end if;
  -- vatandaş: boş liste (return query hiç çalışmadı, fonksiyon boş döner).
end;
$$;


ALTER FUNCTION "public"."get_dm_contacts"() OWNER TO "postgres";


GRANT ALL ON FUNCTION "public"."get_dm_contacts"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_dm_contacts"() TO "service_role";


--
-- get_or_create_dm_conversation() — izin verilen bir kişiyle (personel↔kendi
-- müdürü, müdür↔admin) var olan konuşmayı döndürür, yoksa oluşturur.
--
CREATE OR REPLACE FUNCTION "public"."get_or_create_dm_conversation"("p_other_user_id" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_caller uuid := auth.uid();
  v_caller_role text;
  v_caller_dept bigint;
  v_other_role text;
  v_other_dept bigint;
  v_other_active boolean;
  v_low uuid;
  v_high uuid;
  v_conversation_id uuid;
begin
  if v_caller is null then
    raise exception 'Giriş yapmanız gerekiyor.';
  end if;
  if not public.current_user_is_active() then
    raise exception 'Hesabınız pasifleştirilmiş, mesajlaşma özelliğini kullanamazsınız.';
  end if;
  if v_caller = p_other_user_id then
    raise exception 'Kendinizle konuşma başlatamazsınız.';
  end if;

  select role, department_id into v_caller_role, v_caller_dept from public.users where id = v_caller;
  select role, department_id, is_active into v_other_role, v_other_dept, v_other_active from public.users where id = p_other_user_id;

  if v_other_role is null then
    raise exception 'Kullanıcı bulunamadı.';
  end if;
  if not coalesce(v_other_active, true) then
    raise exception 'Bu kullanıcı pasifleştirilmiş, mesajlaşma başlatılamaz.';
  end if;

  if (v_caller_role = 'personel' and v_other_role = 'mudur' and not (v_caller_dept is distinct from v_other_dept)) then
    -- personel → kendi biriminin müdürü: izinli
  elsif (v_caller_role = 'mudur' and v_other_role = 'personel' and not (v_caller_dept is distinct from v_other_dept)) then
    -- müdür → kendi biriminin personeli: izinli
  elsif (v_caller_role = 'mudur' and v_other_role = 'admin') then
    -- müdür → admin: izinli
  elsif (v_caller_role = 'admin' and v_other_role = 'mudur') then
    -- admin → müdür: izinli
  else
    raise exception 'Bu kullanıcıyla mesajlaşma izniniz yok.';
  end if;

  if v_caller < p_other_user_id then
    v_low := v_caller; v_high := p_other_user_id;
  else
    v_low := p_other_user_id; v_high := v_caller;
  end if;

  select id into v_conversation_id from public.dm_conversations
    where participant_a = v_low and participant_b = v_high;

  if v_conversation_id is null then
    insert into public.dm_conversations (participant_a, participant_b)
    values (v_low, v_high)
    returning id into v_conversation_id;
  end if;

  return v_conversation_id;
end;
$$;


ALTER FUNCTION "public"."get_or_create_dm_conversation"("p_other_user_id" "uuid") OWNER TO "postgres";


GRANT ALL ON FUNCTION "public"."get_or_create_dm_conversation"("p_other_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_or_create_dm_conversation"("p_other_user_id" "uuid") TO "service_role";


--
-- get_my_dm_conversations() — konuşma listesi ekranı için: karşı tarafın
-- bilgisi (users RLS'ini bypass ederek), son mesaj önizlemesi, okunmamış
-- sayısı. `users` tablosuna JOIN gerektirdiği için security definer.
--
CREATE OR REPLACE FUNCTION "public"."get_my_dm_conversations"() RETURNS TABLE(
    "conversation_id" "uuid",
    "other_user_id" "uuid",
    "other_full_name" "text",
    "other_role" "text",
    "other_avatar_url" "text",
    "last_message_body" "text",
    "last_message_at" timestamp with time zone,
    "last_message_sender_id" "uuid",
    "unread_count" bigint
)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Giriş yapmanız gerekiyor.';
  end if;

  return query
    select
      c.id,
      other.id,
      other.full_name,
      other.role,
      other.avatar_url,
      lm.body,
      lm.created_at,
      lm.sender_id,
      (
        select count(*) from public.dm_messages m
        where m.conversation_id = c.id
          and (m.sender_id is distinct from v_uid)
          and m.created_at > coalesce(
            case when c.participant_a = v_uid then c.participant_a_last_read_at else c.participant_b_last_read_at end,
            'epoch'::timestamptz
          )
      )
    from public.dm_conversations c
    join public.users other on other.id = (case when c.participant_a = v_uid then c.participant_b else c.participant_a end)
    left join lateral (
      select m2.body, m2.created_at, m2.sender_id
      from public.dm_messages m2
      where m2.conversation_id = c.id
      order by m2.created_at desc
      limit 1
    ) lm on true
    where (c.participant_a = v_uid or c.participant_b = v_uid)
    order by coalesce(lm.created_at, c.created_at) desc;
end;
$$;


ALTER FUNCTION "public"."get_my_dm_conversations"() OWNER TO "postgres";


GRANT ALL ON FUNCTION "public"."get_my_dm_conversations"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_my_dm_conversations"() TO "service_role";


--
-- mark_dm_conversation_read() — konuşma ekranı açılınca çağrılır, çağıranın
-- last_read_at'ini şimdiye çeker (okunmamış sayacı bunu baz alıyor).
--
CREATE OR REPLACE FUNCTION "public"."mark_dm_conversation_read"("p_conversation_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_uid uuid := auth.uid();
begin
  update public.dm_conversations
    set participant_a_last_read_at = case when participant_a = v_uid then now() else participant_a_last_read_at end,
        participant_b_last_read_at = case when participant_b = v_uid then now() else participant_b_last_read_at end
  where id = p_conversation_id and (participant_a = v_uid or participant_b = v_uid);
end;
$$;


ALTER FUNCTION "public"."mark_dm_conversation_read"("p_conversation_id" "uuid") OWNER TO "postgres";


GRANT ALL ON FUNCTION "public"."mark_dm_conversation_read"("p_conversation_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mark_dm_conversation_read"("p_conversation_id" "uuid") TO "service_role";


--
-- handle_new_dm_message() — yeni mesaj eklenince (1) konuşmanın
-- last_message_at'ini güncelle, (2) karşı tarafa uygulama içi bildirim
-- gönder (`notifications.conversation_id` dolu, `request_id` NULL —
-- `notifications_screen.dart` bu durumda talep yerine DM ekranını açar).
--
CREATE OR REPLACE FUNCTION "public"."handle_new_dm_message"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_conversation record;
  v_recipient uuid;
  v_sender_name text;
begin
  select * into v_conversation from public.dm_conversations where id = new.conversation_id;

  update public.dm_conversations set last_message_at = new.created_at where id = new.conversation_id;

  if v_conversation.participant_a = new.sender_id then
    v_recipient := v_conversation.participant_b;
  else
    v_recipient := v_conversation.participant_a;
  end if;

  select full_name into v_sender_name from public.users where id = new.sender_id;

  insert into public.notifications (user_id, request_id, conversation_id, message)
  values (
    v_recipient,
    null,
    new.conversation_id,
    coalesce(v_sender_name, 'Biri') || ' size mesaj gönderdi: ' ||
      (case when length(new.body) > 60 then left(new.body, 60) || '…' else new.body end)
  );

  return new;
end;
$$;


ALTER FUNCTION "public"."handle_new_dm_message"() OWNER TO "postgres";


CREATE TRIGGER "on_dm_message_created" AFTER INSERT ON "public"."dm_messages" FOR EACH ROW EXECUTE FUNCTION "public"."handle_new_dm_message"();


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

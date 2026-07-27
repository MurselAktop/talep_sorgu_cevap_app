-- Onaylanmış (status = 'onaylandi') talepler, resolved_at üzerinden 3 ay
-- (90 gün) geçince otomatik silinir. CASCADE ile attachments/results/
-- ratings/history/notifications da temizlenir. Uygulama açılışında
-- check_sla_breaches gibi fire-and-forget çağrılır.

CREATE OR REPLACE FUNCTION "public"."purge_expired_requests"() RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_deleted integer := 0;
begin
  -- Pasif kullanıcılar da dahil, temizlik herkese açık bir bakım işi;
  -- auth zorunlu değil ama istemci authenticated oturumla çağırıyor.
  delete from public.requests
  where status = 'onaylandi'
    and resolved_at is not null
    and resolved_at < (now() - interval '90 days');

  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

ALTER FUNCTION "public"."purge_expired_requests"() OWNER TO "postgres";
GRANT ALL ON FUNCTION "public"."purge_expired_requests"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."purge_expired_requests"() TO "service_role";

// Admin/müdür rapor onayı (2026-07-27)
//
// Neden Edge Function?
// `results` tablosunda UPDATE RLS politikası yalnızca `role = mudur` için vardı.
// Web paneli admin'e Onayla/Reddet gösteriyordu; PostgREST RLS yüzünden 0 satır
// güncelleyip hata döndürmediği için buton "çalışmıyor" görünüyordu.
// Bu fonksiyon JWT'deki kullanıcıyı doğrular (admin veya ilgili birimin müdürü),
// sonra service_role ile günceller — RLS bypass bilinçli ve yetki kontrollüdür.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization") || "";
    if (!authHeader.startsWith("Bearer ")) {
      return json({ error: "Oturum gerekli." }, 401);
    }

    const { result_id, status } = await req.json();
    if (!result_id || (status !== "onaylandi" && status !== "reddedildi")) {
      return json({ error: "Geçersiz istek." }, 400);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const adminClient = createClient(supabaseUrl, serviceKey);

    const { data: userData, error: userErr } = await userClient.auth.getUser();
    if (userErr || !userData.user) {
      return json({ error: "Oturum geçersiz." }, 401);
    }
    const uid = userData.user.id;

    const { data: profile, error: profileErr } = await adminClient
      .from("users")
      .select("id, role, department_id, is_active")
      .eq("id", uid)
      .maybeSingle();

    if (profileErr || !profile) {
      return json({ error: "Profil bulunamadı." }, 403);
    }
    if (profile.is_active === false) {
      return json({ error: "Hesabınız pasifleştirilmiş." }, 403);
    }

    const { data: resultRow, error: resultErr } = await adminClient
      .from("results")
      .select("id, request_id, approval_status")
      .eq("id", result_id)
      .maybeSingle();

    if (resultErr || !resultRow) {
      return json({ error: "Rapor bulunamadı." }, 404);
    }
    if (resultRow.approval_status !== "beklemede") {
      return json({ error: "Bu rapor için onay beklenmiyor." }, 409);
    }

    const { data: requestRow, error: reqErr } = await adminClient
      .from("requests")
      .select("id, department_id")
      .eq("id", resultRow.request_id)
      .maybeSingle();

    if (reqErr || !requestRow) {
      return json({ error: "Talep bulunamadı." }, 404);
    }

    const role = profile.role as string;
    const allowed =
      role === "admin" ||
      (role === "mudur" &&
        profile.department_id != null &&
        profile.department_id === requestRow.department_id);

    if (!allowed) {
      return json({
        error: "Bu raporu onaylama/reddetme yetkiniz yok.",
      }, 403);
    }

    const { data: updated, error: updErr } = await adminClient
      .from("results")
      .update({
        approval_status: status,
        approved_by: uid,
      })
      .eq("id", result_id)
      .eq("approval_status", "beklemede")
      .select("id, approval_status")
      .maybeSingle();

    if (updErr) {
      console.error("update error", updErr);
      return json({ error: "Güncelleme başarısız." }, 500);
    }
    if (!updated) {
      return json({ error: "Rapor güncellenemedi (eşzamanlı değişiklik olabilir)." }, 409);
    }

    return json({
      ok: true,
      approval_status: updated.approval_status,
    });
  } catch (err) {
    console.error("set-result-approval error", err);
    return json({ error: "Beklenmeyen bir hata oluştu." }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

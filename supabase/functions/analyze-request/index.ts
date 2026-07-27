// Arıza Talep Asistanı (2026-07-27, çok turlu sohbet desteğiyle güncellendi) —
// Gemini API ile talep metni ön analizi.
//
// GÜVENLİK: Gemini API anahtarı SADECE burada, sunucu tarafı bir Supabase
// secret'ı (`GEMINI_API_KEY`, `supabase secrets set` ile ayarlanır) olarak
// tutulur — Flutter uygulamasına asla gömülmez (bkz. CLAUDE.md, "Gemini ile
// talep yorumlama" bölümündeki güvenlik kuralı — kullanıcıyla 2026-07-27'de
// `flutter_dotenv`/`google_generative_ai` ile client-side çağrı YERİNE bu
// mimarinin bilinçli olarak korunmasına karar verildi). Flutter tarafı sadece
// bu fonksiyonu `supabase.functions.invoke(...)` ile çağırır, anahtarı hiçbir
// zaman görmez.
//
// Asistan BİLİNÇLİ olarak genel bir sohbet botu DEĞİL — `responseSchema` ile
// zorlanan katı JSON çıktısı, modelin serbest metinle "sohbet etmesini"
// yapısal olarak engelliyor; her turda sadece üç alanlı (quick_fixes,
// department_name, department_reason) bir analiz sonucu üretebiliyor. UI
// tarafı bunu "sohbet" gibi GÖSTERİYOR (kullanıcı mesaj yazıp devam
// edebiliyor, ör. "denedim ama olmadı") ama her assistan yanıtı yine aynı
// katı şemaya uymak zorunda.

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SYSTEM_INSTRUCTION = `Sen sadece bir Arıza Talep Ön Çözüm Asistanısın. Asla genel sohbet, hava durumu veya arıza dışı konulara yanıt verme.

Görevin:
1. Kullanıcının yazdığı sorunu (ve varsa önceki mesajlarını, ör. "denedim ama olmadı") incele.
2. Evde/ofiste uygulanabilecek EN FAZLA 2-3 pratik çözüm öner (quick_fixes alanı). Kullanıcı zaten bir şeyi denediğini söylediyse, AYNI öneriyi tekrarlama, farklı öneriler sun.
3. Bu çözümler sorunu çözmezse VEYA sorun açıkça donanımsal/kurumsalsa, sistemde kayıtlı hangi birime talep açması gerektiğini belirle (department_name alanı) ve kısa bir gerekçe yaz (department_reason alanı).
4. department_name SADECE sana verilen "geçerli birimler" listesinden BİREBİR bir isim olmalı. Hiçbir eşleşme yoksa department_name alanını null bırak.
5. Konu bir arıza/sorun tanımı DEĞİLSE (ör. hava durumu, genel sohbet, şaka, alakasız soru): quick_fixes'i boş bırak, department_name'i null bırak, department_reason alanına tam olarak şu Türkçe mesajı yaz: "Bu bir arıza bildirisi değil. Lütfen yaşadığınız arıza veya sorunu yazınız."
6. Yanıtın HER ZAMAN verilen JSON şemasına uymalı, şema dışında hiçbir metin üretme.`;

const RESPONSE_SCHEMA = {
  type: "OBJECT",
  properties: {
    quick_fixes: {
      type: "ARRAY",
      items: { type: "STRING" },
      description: "En fazla 3 adet kısa, pratik çözüm önerisi.",
    },
    department_name: {
      type: "STRING",
      nullable: true,
      description: "Verilen listeden birebir bir birim adı, veya uygun eşleşme yoksa null.",
    },
    department_reason: {
      type: "STRING",
      description: "Birim önerisinin (veya önerilmemesinin) kısa gerekçesi.",
    },
  },
  required: ["quick_fixes", "department_reason"],
};

// "gemini-flash-lite-latest" bilinçli tercih:
// - "gemini-flash-latest" → gemini-3.6-flash'e çözümleniyor ve free-tier'da
//   günde yalnızca ~20 istek kotası var; kota dolunca 429 → asistan "çalışmıyor"
//   gibi görünüyordu (2026-07-27 canlı teşhis).
// - Lite takma adı daha yüksek free-tier kota sunuyor ve eski sabit sürümlerin
//   ("2.5-flash-lite" vb.) "no longer available to new users" 404'ünden kaçınıyor.
const GEMINI_MODEL = "gemini-flash-lite-latest";

interface ChatTurn {
  role: "user" | "model";
  text: string;
  image_base64?: string;
  image_mime_type?: string;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { messages, departments } = await req.json();

    if (!Array.isArray(messages) || messages.length === 0) {
      return new Response(
        JSON.stringify({ error: "Lütfen sorununuzu en az birkaç kelimeyle açıklayın." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const turns: ChatTurn[] = messages
      .filter((m: unknown) =>
        typeof m === "object" && m !== null &&
        typeof (m as ChatTurn).text === "string" &&
        ((m as ChatTurn).role === "user" || (m as ChatTurn).role === "model")
      )
      .map((m: ChatTurn) => ({
        role: m.role,
        text: m.text,
        image_base64: typeof m.image_base64 === "string" ? m.image_base64 : undefined,
        image_mime_type: typeof m.image_mime_type === "string" ? m.image_mime_type : undefined,
      }));

    const lastTurn = turns[turns.length - 1];
    const hasImage = !!(lastTurn?.image_base64 && lastTurn.image_base64.length > 0);
    if (!lastTurn || lastTurn.role !== "user" || (lastTurn.text.trim().length < 2 && !hasImage)) {
      return new Response(
        JSON.stringify({ error: "Lütfen sorununuzu en az birkaç kelimeyle açıklayın veya bir fotoğraf ekleyin." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const apiKey = Deno.env.get("GEMINI_API_KEY");
    if (!apiKey) {
      console.error("GEMINI_API_KEY secret tanımlı değil.");
      return new Response(
        JSON.stringify({ error: "Asistan şu anda kullanılamıyor. Lütfen daha sonra tekrar deneyin." }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const departmentNames: string[] = Array.isArray(departments)
      ? departments.filter((d) => typeof d === "string" && d.trim().length > 0)
      : [];
    const departmentListText = departmentNames.length > 0
      ? departmentNames.join(", ")
      : "(liste boş — department_name'i her zaman null bırak)";

    const contents = turns.map((t) => {
      const parts: Array<Record<string, unknown>> = [];
      const text = t.text.trim().length > 0
        ? t.text
        : (t.image_base64 ? "Eklediğim fotoğraftaki arızayı/sorunu incele." : "");
      if (text.length > 0) parts.push({ text });
      if (t.role === "user" && t.image_base64) {
        parts.push({
          inlineData: {
            mimeType: t.image_mime_type || "image/jpeg",
            data: t.image_base64,
          },
        });
      }
      return { role: t.role, parts };
    });

    const geminiResp = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-goog-api-key": apiKey,
        },
        body: JSON.stringify({
          systemInstruction: {
            parts: [{
              text: `${SYSTEM_INSTRUCTION}

Geçerli birimler: ${departmentListText}

Kullanıcı bir fotoğraf eklediyse görseldeki arızayı/sorunu da dikkate al.`,
            }],
          },
          contents,
          generationConfig: {
            responseMimeType: "application/json",
            responseSchema: RESPONSE_SCHEMA,
            temperature: 0.2,
          },
        }),
      },
    );

    if (!geminiResp.ok) {
      const errText = await geminiResp.text();
      console.error("Gemini API hatası:", geminiResp.status, errText);
      let userMessage =
        "Asistan şu anda yanıt veremiyor. Lütfen daha sonra tekrar deneyin.";
      if (geminiResp.status === 429) {
        userMessage =
          "Asistan kotası şu an dolu (ücretsiz Gemini limiti). Lütfen bir dakika sonra tekrar deneyin.";
      } else if (geminiResp.status === 401 || geminiResp.status === 403) {
        userMessage =
          "Asistan yapılandırması geçersiz. Yöneticiye bildirin (Gemini API anahtarı).";
      }
      return new Response(
        JSON.stringify({ error: userMessage }),
        {
          status: geminiResp.status === 429 ? 429 : 502,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const geminiData = await geminiResp.json();
    const rawText = geminiData?.candidates?.[0]?.content?.parts?.[0]?.text;
    if (typeof rawText !== "string") {
      console.error("Gemini yanıtı beklenmeyen formatta:", JSON.stringify(geminiData));
      return new Response(
        JSON.stringify({ error: "Asistan bir yanıt üretemedi. Lütfen tekrar deneyin." }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const parsed = JSON.parse(rawText);
    return new Response(JSON.stringify(parsed), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("analyze-request beklenmeyen hata:", err);
    return new Response(
      JSON.stringify({ error: "Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin." }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});

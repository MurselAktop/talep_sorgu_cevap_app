<script setup lang="ts">
const route = useRoute()
const { user, isAdmin, isMudur } = useAuth()
const supabase = useSupabase()

const id = computed(() => String(route.params.id))
const request = ref<any>(null)
const result = ref<any>(null)
const history = ref<any[]>([])
const attachments = ref<{ id: string; file_url: string; media_type: string; signedUrl?: string | null }[]>([])
const personnel = ref<any[]>([])
const departments = ref<any[]>([])
const loading = ref(true)
const actionLoading = ref(false)
const message = ref('')
const messageTone = ref<'ok' | 'err'>('ok')
const reportText = ref('')
const assignTo = ref('')
const newDept = ref<number | null>(null)
const previewSrc = ref<string | null>(null)
const lightbox = ref<{ show: () => void } | null>(null)

const historyLabels: Record<string, string> = {
  created: 'Oluşturuldu',
  assigned: 'Atandı',
  department_changed: 'Birim değişti',
  resolved: 'Çözüm raporu yazıldı',
  report_resubmitted: 'Rapor yeniden gönderildi',
  approved: 'Onaylandı',
  rejected: 'Reddedildi',
  reopened: 'Yeniden açıldı',
  rated: 'Değerlendirildi',
}

const assigneeName = computed(() => {
  const a = request.value?.assignee
  if (!a) return null
  return Array.isArray(a) ? a[0]?.full_name : a.full_name
})
const isCreator = computed(() => request.value?.created_by === user.value?.id)
const isAssignee = computed(() => request.value?.assigned_to === user.value?.id)
const canAssign = computed(
  () =>
    (isMudur.value || isAdmin.value)
    && request.value?.status === 'acik'
    && !request.value?.assigned_to,
)
const canResolve = computed(
  () => isAssignee.value && ['acik', 'reddedildi'].includes(String(request.value?.status || '')),
)
const canApprove = computed(
  () => (isMudur.value || isAdmin.value) && result.value?.approval_status === 'beklemede',
)

function flash(text: string, tone: 'ok' | 'err' = 'ok') {
  message.value = text
  messageTone.value = tone
}

function openAttachment(a: { signedUrl?: string | null; file_url: string; media_type: string }) {
  if (a.media_type === 'image' && a.signedUrl) {
    previewSrc.value = a.signedUrl
    nextTick(() => lightbox.value?.show())
    return
  }
  // video/belge: imzalı URL aç
  void (async () => {
    const { data } = await supabase.storage.from('request-attachments').createSignedUrl(a.file_url, 120)
    if (data?.signedUrl) window.open(data.signedUrl, '_blank', 'noopener')
  })()
}

async function load() {
  loading.value = true
  try {
    const { data: req, error } = await supabase
      .from('requests')
      .select('*, departments(name), assignee:users!requests_assigned_to_fkey(full_name)')
      .eq('id', id.value)
      .maybeSingle()
    if (error) throw error
    request.value = req
    if (req?.assigned_to) assignTo.value = ''

    const { data: res } = await supabase
      .from('results')
      .select('*')
      .eq('request_id', id.value)
      .maybeSingle()
    result.value = res
    if (res?.report_text) reportText.value = res.report_text

    const { data: hist } = await supabase
      .from('request_history')
      .select('*')
      .eq('request_id', id.value)
      .order('created_at', { ascending: true })
    history.value = hist || []

    const { data: atts } = await supabase
      .from('attachments')
      .select('id, file_url, media_type')
      .eq('request_id', id.value)
      .order('created_at', { ascending: true })
    const list = atts || []
    attachments.value = await Promise.all(
      list.map(async (a: any) => {
        if (a.media_type !== 'image') return { ...a, signedUrl: null }
        try {
          const { data } = await supabase.storage
            .from('request-attachments')
            .createSignedUrl(a.file_url, 3600)
          return { ...a, signedUrl: data?.signedUrl || null }
        } catch {
          return { ...a, signedUrl: null }
        }
      }),
    )

    if ((isMudur.value || isAdmin.value) && req?.department_id) {
      const { data: people } = await supabase
        .from('users')
        .select('id, full_name')
        .eq('department_id', req.department_id)
        .eq('role', 'personel')
        .eq('is_active', true)
      personnel.value = people || []
    }

    if (isAdmin.value || isMudur.value) {
      const { data: deps } = await supabase
        .from('departments')
        .select('id, name')
        .eq('is_active', true)
        .order('name')
      departments.value = deps || []
    }
  } catch (e: any) {
    flash(e?.message || 'Yüklenemedi.', 'err')
  } finally {
    loading.value = false
  }
}

async function assign() {
  if (!assignTo.value || actionLoading.value) return
  actionLoading.value = true
  try {
    const { data, error } = await supabase
      .from('requests')
      .update({ assigned_to: assignTo.value })
      .eq('id', id.value)
      .select('id')
    if (error) throw error
    if (!data?.length) throw new Error('Atama yapılamadı (yetki veya durum).')
    flash('Personel atandı.')
    await load()
  } catch (e: any) {
    flash(e?.message || 'Atama başarısız.', 'err')
  } finally {
    actionLoading.value = false
  }
}

async function saveReport() {
  if (!reportText.value.trim() || actionLoading.value) return
  actionLoading.value = true
  try {
    if (result.value) {
      const { data, error } = await supabase
        .from('results')
        .update({ report_text: reportText.value.trim(), approval_status: 'beklemede' })
        .eq('id', result.value.id)
        .select('id')
      if (error) throw error
      if (!data?.length) throw new Error('Rapor güncellenemedi (yetki).')
      flash('Rapor güncellendi, onay bekleniyor.')
    } else {
      const { data, error } = await supabase
        .from('results')
        .insert({
          request_id: id.value,
          report_text: reportText.value.trim(),
          resolved_by: user.value?.id,
          approval_status: 'beklemede',
        })
        .select('id')
      if (error) throw error
      if (!data?.length) throw new Error('Rapor kaydedilemedi (yetki).')
      flash('Rapor kaydedildi, onay bekleniyor.')
    }
    await load()
  } catch (e: any) {
    flash(e?.message || 'Rapor kaydedilemedi.', 'err')
  } finally {
    actionLoading.value = false
  }
}

async function setApproval(status: 'onaylandi' | 'reddedildi') {
  if (!result.value || actionLoading.value) return
  actionLoading.value = true
  try {
    // Admin için results UPDATE RLS'i yoktu (sadece müdür vardı) —
    // Edge Function yetki kontrolü + service_role ile güvenli günceller.
    const { data, error } = await supabase.functions.invoke('set-result-approval', {
      body: { result_id: result.value.id, status },
    })
    const bodyError =
      data && typeof data === 'object' && typeof (data as any).error === 'string'
        ? ((data as any).error as string)
        : null
    if (error || bodyError) {
      throw new Error(bodyError || error?.message || 'İşlem başarısız.')
    }
    flash(status === 'onaylandi' ? 'Talep onaylandı.' : 'Talep reddedildi, personele geri döndü.')
    await load()
  } catch (e: any) {
    flash(e?.message || 'İşlem başarısız.', 'err')
  } finally {
    actionLoading.value = false
  }
}

async function reassign() {
  if (!newDept.value || actionLoading.value) return
  actionLoading.value = true
  try {
    const { error } = await supabase.rpc('reassign_request_department', {
      p_request_id: id.value,
      p_new_department_id: newDept.value,
    })
    if (error) throw error
    flash('Birim değiştirildi.')
    await load()
  } catch (e: any) {
    flash(e?.message || 'Yönlendirme başarısız.', 'err')
  } finally {
    actionLoading.value = false
  }
}

async function cancelRequest() {
  if (request.value?.assigned_to) {
    flash('Talebiniz ilgili birim personeline atanmıştır, şu an talepte değişiklik yapılamaz.', 'err')
    return
  }
  if (actionLoading.value) return
  actionLoading.value = true
  try {
    const { data, error } = await supabase
      .from('requests')
      .update({ status: 'iptal' })
      .eq('id', id.value)
      .select('id')
    if (error) throw error
    if (!data?.length) throw new Error('İptal edilemedi.')
    flash('Talep iptal edildi.')
    await load()
  } catch (e: any) {
    flash(e?.message || 'İptal başarısız.', 'err')
  } finally {
    actionLoading.value = false
  }
}

onMounted(load)
</script>

<template>
  <div>
    <PageHeader title="Talep Detayı" subtitle="Durum, rapor ve işlem geçmişi">
      <template #actions>
        <NuxtLink to="/requests/incoming" class="btn-secondary text-xs">← Listeye dön</NuxtLink>
      </template>
    </PageHeader>

    <p v-if="loading" class="text-sm text-gray-500">Yükleniyor…</p>

    <div v-else-if="request" class="mx-auto max-w-3xl space-y-4">
      <div
        v-if="message"
        class="rounded-xl px-4 py-3 text-[13px]"
        :class="messageTone === 'ok'
          ? 'border border-teal-500/30 bg-teal-500/10 text-teal-700 dark:text-teal-300'
          : 'border border-red-500/30 bg-red-500/10 text-red-700 dark:text-red-300'"
      >
        {{ message }}
      </div>

      <!-- Ana bilgi -->
      <section class="card space-y-3 p-5">
        <div class="flex flex-wrap items-start justify-between gap-3">
          <h2 class="text-lg font-semibold leading-snug text-gray-900 dark:text-white">
            {{ request.title }}
          </h2>
          <StatusBadge :status="request.status" />
        </div>
        <p class="whitespace-pre-wrap text-[13px] leading-6 text-gray-600 dark:text-gray-300">
          {{ request.description }}
        </p>
        <div class="flex flex-wrap gap-2 border-t border-gray-200/70 pt-3 text-[11px] text-gray-500 dark:border-gray-700/70">
          <span class="rounded-lg bg-gray-100 px-2 py-1 dark:bg-gray-900">{{ request.departments?.name || '—' }}</span>
          <span class="rounded-lg bg-gray-100 px-2 py-1 dark:bg-gray-900">{{ request.category || '—' }}</span>
          <span class="rounded-lg bg-gray-100 px-2 py-1 dark:bg-gray-900">
            {{ new Date(request.created_at).toLocaleString('tr-TR') }}
          </span>
          <span v-if="request.requester_type" class="rounded-lg bg-gray-100 px-2 py-1 dark:bg-gray-900">
            {{ request.requester_type }}
          </span>
          <span
            v-if="request.assigned_to"
            class="rounded-lg bg-blue-500/15 px-2 py-1 font-medium text-blue-700 dark:text-blue-300"
          >
            Atanan: {{ assigneeName || 'Personel' }}
          </span>
          <span
            v-else
            class="rounded-lg bg-amber-500/15 px-2 py-1 text-amber-700 dark:text-amber-300"
          >
            Henüz atanmadı
          </span>
        </div>
      </section>

      <!-- Ekler -->
      <section v-if="attachments.length" class="card space-y-3 p-5">
        <h3 class="text-[13px] font-semibold text-gray-900 dark:text-white">Ekler</h3>
        <div class="grid grid-cols-2 gap-3 sm:grid-cols-3">
          <button
            v-for="a in attachments"
            :key="a.id"
            type="button"
            class="group overflow-hidden rounded-xl border border-gray-200 text-left transition hover:border-blue-400/50 dark:border-gray-700"
            @click="openAttachment(a)"
          >
            <img
              v-if="a.media_type === 'image' && a.signedUrl"
              :src="a.signedUrl"
              alt="Ek"
              class="aspect-square w-full object-cover"
            />
            <div
              v-else
              class="flex aspect-square flex-col items-center justify-center gap-1 bg-gray-100 px-2 dark:bg-gray-900"
            >
              <svg class="h-8 w-8 text-gray-400" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75">
                <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
                <path d="M14 2v6h6" />
              </svg>
              <span class="text-[11px] capitalize text-gray-500">{{ a.media_type }}</span>
            </div>
            <p class="truncate px-2 py-1.5 text-[10px] text-blue-600 group-hover:underline dark:text-blue-400">
              {{ a.media_type === 'image' ? 'Büyüt' : 'Aç' }}
            </p>
          </button>
        </div>
        <AvatarLightbox ref="lightbox" :src="previewSrc" alt="Ek görsel" />
      </section>

      <!-- Atama: yalnız henüz atanmamış açık talepler -->
      <section v-if="canAssign" class="card space-y-3 p-5">
        <h3 class="text-[13px] font-semibold text-gray-900 dark:text-white">Personele Ata</h3>
        <select v-model="assignTo" class="w-full">
          <option value="" disabled>Personel seçin</option>
          <option v-for="p in personnel" :key="p.id" :value="p.id">{{ p.full_name }}</option>
        </select>
        <button
          class="btn-primary"
          type="button"
          :disabled="actionLoading || !assignTo"
          @click="assign"
        >
          {{ actionLoading ? 'Atanıyor…' : 'Ata' }}
        </button>
      </section>

      <!-- Birim değiştir -->
      <section v-if="(isMudur || isAdmin) && request.status === 'acik'" class="card space-y-3 p-5">
        <h3 class="text-[13px] font-semibold text-gray-900 dark:text-white">Birim Değiştir</h3>
        <select v-model="newDept" class="w-full">
          <option :value="null" disabled>Birim seçin</option>
          <option v-for="d in departments" :key="d.id" :value="d.id">{{ d.name }}</option>
        </select>
        <button class="btn-secondary" type="button" :disabled="actionLoading" @click="reassign">Yönlendir</button>
      </section>

      <!-- Çözüm yaz -->
      <section v-if="canResolve" class="card space-y-3 p-5">
        <h3 class="text-[13px] font-semibold text-gray-900 dark:text-white">Çözüm Raporu</h3>
        <textarea v-model="reportText" rows="5" class="w-full" placeholder="Yaptığınız çözümü yazın…" />
        <button class="btn-primary" type="button" :disabled="actionLoading" @click="saveReport">
          Kaydet / Onaya Gönder
        </button>
      </section>

      <!-- Mevcut rapor + onay -->
      <section v-if="result" class="card space-y-3 p-5">
        <div class="flex flex-wrap items-center justify-between gap-2">
          <h3 class="text-[13px] font-semibold text-gray-900 dark:text-white">Mevcut Rapor</h3>
          <span
            class="rounded-full px-2.5 py-0.5 text-[11px] font-medium"
            :class="{
              'bg-amber-500/15 text-amber-600 dark:text-amber-400': result.approval_status === 'beklemede',
              'bg-teal-500/15 text-teal-600 dark:text-teal-400': result.approval_status === 'onaylandi',
              'bg-red-500/15 text-red-600 dark:text-red-400': result.approval_status === 'reddedildi',
            }"
          >
            {{
              result.approval_status === 'beklemede' ? 'Onay bekliyor'
              : result.approval_status === 'onaylandi' ? 'Onaylandı'
              : result.approval_status === 'reddedildi' ? 'Reddedildi'
              : result.approval_status
            }}
          </span>
        </div>
        <p class="whitespace-pre-wrap rounded-xl bg-gray-50 px-3 py-3 text-[13px] leading-6 text-gray-700 dark:bg-gray-900/60 dark:text-gray-200">
          {{ result.report_text }}
        </p>
        <div v-if="canApprove" class="flex flex-wrap gap-2 pt-1">
          <button
            class="btn-primary min-w-[120px]"
            type="button"
            :disabled="actionLoading"
            @click="setApproval('onaylandi')"
          >
            {{ actionLoading ? '…' : 'Onayla' }}
          </button>
          <button
            class="btn-danger min-w-[120px]"
            type="button"
            :disabled="actionLoading"
            @click="setApproval('reddedildi')"
          >
            Reddet
          </button>
        </div>
      </section>

      <section v-if="isCreator && !request.assigned_to && request.status === 'acik'" class="card p-5">
        <button class="btn-danger" type="button" :disabled="actionLoading" @click="cancelRequest">
          Talebi İptal Et
        </button>
      </section>

      <!-- Geçmiş -->
      <section v-if="history.length" class="card p-5">
        <h3 class="mb-4 text-[13px] font-semibold text-gray-900 dark:text-white">Geçmiş</h3>
        <ol class="relative space-y-4 border-l border-gray-200 pl-4 dark:border-gray-700">
          <li v-for="h in history" :key="h.id" class="relative">
            <span class="absolute -left-[21px] top-1.5 h-2.5 w-2.5 rounded-full bg-blue-500 shadow-[0_0_0_3px_rgba(59,130,246,0.2)]" />
            <p class="text-[13px] font-medium text-gray-800 dark:text-gray-100">
              {{ historyLabels[h.event_type] || h.event_type }}
              <span class="font-normal text-gray-500">— {{ h.actor_label || 'Sistem' }}</span>
            </p>
            <p class="mt-0.5 text-[11px] text-gray-400">
              {{ new Date(h.created_at).toLocaleString('tr-TR') }}
            </p>
          </li>
        </ol>
      </section>
    </div>

    <p v-else class="text-sm text-gray-500">Talep bulunamadı veya görüntüleme yetkiniz yok.</p>
  </div>
</template>

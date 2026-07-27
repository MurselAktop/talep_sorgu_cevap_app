<script setup lang="ts">
const { user, role } = useAuth()
const supabase = useSupabase()
const route = useRoute()
const { openChat: openAiChat } = useAiAssistant()

const MAX_FILES = 8
const MAX_BYTES = 10 * 1024 * 1024 // 10 MB

type PendingFile = {
  id: string
  file: File
  previewUrl: string | null
  mediaType: 'image' | 'video' | 'document'
}

const title = ref((route.query.title as string) || '')
const description = ref((route.query.description as string) || '')
const category = ref('')
const departmentId = ref<number | null>(
  route.query.departmentId ? Number(route.query.departmentId) : null,
)
const departments = ref<any[]>([])
const pendingFiles = ref<PendingFile[]>([])
const fileInput = ref<HTMLInputElement | null>(null)
const loading = ref(false)
const error = ref('')
const success = ref('')
const uploadWarning = ref('')

const selectedDeptName = computed(() => {
  const d = departments.value.find((x) => x.id === departmentId.value)
  return d?.name || null
})

const descLen = computed(() => description.value.trim().length)
const canSubmit = computed(
  () =>
    title.value.trim().length > 0
    && description.value.trim().length > 0
    && category.value.trim().length > 0
    && departmentId.value != null
    && !loading.value,
)

onMounted(async () => {
  const { data } = await supabase.from('departments').select('id, name').eq('is_active', true).order('name')
  departments.value = data || []
  if (route.query.departmentName) {
    const match = departments.value.find((d) => d.name === route.query.departmentName)
    if (match) departmentId.value = match.id
  }
})

onUnmounted(() => {
  for (const p of pendingFiles.value) {
    if (p.previewUrl) URL.revokeObjectURL(p.previewUrl)
  }
})

function openAssistant() {
  openAiChat()
}

function mediaTypeOf(file: File): PendingFile['mediaType'] {
  if (file.type.startsWith('image/')) return 'image'
  if (file.type.startsWith('video/')) return 'video'
  return 'document'
}

function onFilesPicked(e: Event) {
  const input = e.target as HTMLInputElement
  const files = Array.from(input.files || [])
  input.value = ''
  error.value = ''

  for (const file of files) {
    if (pendingFiles.value.length >= MAX_FILES) {
      error.value = `En fazla ${MAX_FILES} dosya ekleyebilirsiniz.`
      break
    }
    if (file.size > MAX_BYTES) {
      error.value = `"${file.name}" çok büyük (en fazla 10 MB).`
      continue
    }
    const mt = mediaTypeOf(file)
    if (mt === 'image' && !['image/jpeg', 'image/png', 'image/webp'].includes(file.type)) {
      error.value = `"${file.name}" desteklenmeyen görsel formatı (JPEG/PNG/WebP).`
      continue
    }
    pendingFiles.value.push({
      id: `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
      file,
      previewUrl: mt === 'image' ? URL.createObjectURL(file) : null,
      mediaType: mt,
    })
  }
}

function removeFile(id: string) {
  const idx = pendingFiles.value.findIndex((p) => p.id === id)
  if (idx < 0) return
  const [removed] = pendingFiles.value.splice(idx, 1)
  if (removed?.previewUrl) URL.revokeObjectURL(removed.previewUrl)
}

function guessMime(file: File) {
  if (file.type) return file.type
  const ext = file.name.toLowerCase().split('.').pop()
  const map: Record<string, string> = {
    jpg: 'image/jpeg',
    jpeg: 'image/jpeg',
    png: 'image/png',
    webp: 'image/webp',
    mp4: 'video/mp4',
    mov: 'video/quicktime',
    pdf: 'application/pdf',
    docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  }
  return map[ext || ''] || 'application/octet-stream'
}

async function uploadAttachments(requestId: string) {
  const failed: string[] = []
  for (const item of pendingFiles.value) {
    try {
      const uniqueName = `${Date.now()}_${item.file.name.replace(/[^\w.\-ğüşıöçĞÜŞİÖÇ ]+/gi, '_')}`
      const storagePath = `${requestId}/${uniqueName}`
      const { error: upErr } = await supabase.storage
        .from('request-attachments')
        .upload(storagePath, item.file, {
          contentType: guessMime(item.file),
          upsert: false,
        })
      if (upErr) throw upErr
      const { error: dbErr } = await supabase.from('attachments').insert({
        request_id: requestId,
        file_url: storagePath,
        media_type: item.mediaType,
      })
      if (dbErr) throw dbErr
    } catch {
      failed.push(item.file.name)
    }
  }
  return failed
}

async function submit() {
  error.value = ''
  success.value = ''
  uploadWarning.value = ''
  loading.value = true
  try {
    const requesterType = role.value === 'vatandas' ? 'vatandas' : 'personel'
    const { data, error: err } = await supabase.rpc('create_request', {
      p_title: title.value.trim(),
      p_description: description.value.trim(),
      p_category: category.value.trim(),
      p_department_id: departmentId.value,
      p_requester_type: requesterType,
      p_created_by: user.value?.id,
    })
    if (err) throw err
    const result = typeof data === 'string' ? JSON.parse(data) : data
    const requestId = String(result.id)

    if (pendingFiles.value.length) {
      const failed = await uploadAttachments(requestId)
      if (failed.length) {
        uploadWarning.value = `Talep oluşturuldu ama şu dosyalar yüklenemedi: ${failed.join(', ')}`
      }
    }

    success.value = 'Talep oluşturuldu.'
    await navigateTo(`/requests/${requestId}`)
  } catch (e: any) {
    error.value = e?.message || 'Talep oluşturulamadı.'
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="mx-auto max-w-4xl">
    <PageHeader title="Talep Oluştur" subtitle="Sorununuzu yazın, birimi seçin ve gönderin" />

    <div
      class="mb-5 flex flex-col gap-3 rounded-2xl border border-blue-500/20 bg-gradient-to-r from-blue-600/10 via-blue-500/5 to-transparent p-4 sm:flex-row sm:items-center sm:justify-between dark:border-blue-400/15"
    >
      <div class="flex items-start gap-3">
        <span class="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-blue-600 text-white shadow-md shadow-blue-500/30">
          <svg class="h-5 w-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M12 5v14M5 12h14" />
          </svg>
        </span>
        <div>
          <p class="text-[13px] font-semibold text-gray-900 dark:text-white">Yeni talep kaydı</p>
          <p class="mt-0.5 text-[12px] leading-4 text-gray-500 dark:text-gray-400">
            Emin değilseniz Arıza Asistanı ile önce pratik çözüm ve birim önerisi alın.
          </p>
        </div>
      </div>
      <button
        type="button"
        class="inline-flex items-center justify-center gap-2 rounded-xl border border-orange-400/40 bg-gradient-to-b from-orange-500 to-orange-600 px-3.5 py-2 text-[12px] font-semibold text-white shadow-md shadow-orange-500/25 hover:from-orange-400 hover:to-orange-500"
        @click="openAssistant"
      >
        <svg class="h-4 w-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <rect x="4" y="8" width="16" height="10" rx="2" />
          <path d="M9 8V6a3 3 0 0 1 6 0v2M9 14h.01M15 14h.01" />
        </svg>
        Arıza Asistanı
      </button>
    </div>

    <form class="card overflow-hidden" @submit.prevent="submit">
      <div class="border-b border-gray-200/80 bg-gradient-to-b from-slate-50/80 to-transparent px-5 py-4 dark:border-gray-700/80 dark:from-gray-800/50 md:px-6">
        <p class="text-[13px] font-semibold text-gray-900 dark:text-white">Talep bilgileri</p>
        <p class="mt-0.5 text-[11px] text-gray-500">Zorunlu alanlar * ile işaretlidir</p>
      </div>

      <div class="space-y-5 p-5 md:p-6">
        <div>
          <label class="flex items-center gap-1.5">
            <svg class="h-3.5 w-3.5 text-blue-500" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M12 20h9M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z" />
            </svg>
            Başlık <span class="text-red-400">*</span>
          </label>
          <input
            v-model="title"
            required
            maxlength="120"
            class="w-full"
            placeholder="Kısa ve net bir başlık yazın"
          />
          <p class="mt-1 text-right text-[10px] text-gray-400">{{ title.length }}/120</p>
        </div>

        <div>
          <div class="mb-1.5 flex items-center justify-between gap-2">
            <label class="mb-0 flex items-center gap-1.5">
              <svg class="h-3.5 w-3.5 text-blue-500" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
                <path d="M14 2v6h6M8 13h8M8 17h6" />
              </svg>
              Açıklama <span class="text-red-400">*</span>
            </label>
            <span class="text-[10px] text-gray-400">{{ descLen }} karakter</span>
          </div>
          <textarea
            v-model="description"
            required
            rows="6"
            class="w-full resize-y min-h-[140px]"
            placeholder="Ne oldu? Nerede / ne zaman başladı? Daha önce denediğiniz bir şey var mı?"
          />
        </div>

        <!-- Görsel / ekler -->
        <div>
          <label class="flex items-center gap-1.5">
            <svg class="h-3.5 w-3.5 text-blue-500" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <rect x="3" y="3" width="18" height="18" rx="2" />
              <circle cx="8.5" cy="8.5" r="1.5" />
              <path d="m21 15-5-5L5 21" />
            </svg>
            Görseller / Ekler
            <span class="font-normal text-gray-400">(isteğe bağlı)</span>
          </label>

          <div
            class="rounded-2xl border border-dashed border-gray-300 bg-slate-50/80 p-4 dark:border-gray-600 dark:bg-gray-900/40"
          >
            <div class="flex flex-col items-start gap-3 sm:flex-row sm:items-center sm:justify-between">
              <p class="text-[12px] leading-4 text-gray-500">
                Fotoğraf, video veya belge ekleyin. En fazla {{ MAX_FILES }} dosya, dosya başı 10 MB.
                <span class="block text-[11px] text-gray-400">JPEG, PNG, WebP, MP4, PDF, DOCX</span>
              </p>
              <button
                type="button"
                class="btn-secondary shrink-0 text-xs"
                :disabled="pendingFiles.length >= MAX_FILES || loading"
                @click="fileInput?.click()"
              >
                <svg class="h-4 w-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                  <path d="M12 5v14M5 12h14" />
                </svg>
                Dosya Seç
              </button>
              <input
                ref="fileInput"
                type="file"
                class="hidden"
                multiple
                accept="image/jpeg,image/png,image/webp,video/mp4,video/quicktime,.pdf,.docx,application/pdf"
                @change="onFilesPicked"
              />
            </div>

            <div v-if="pendingFiles.length" class="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4">
              <div
                v-for="item in pendingFiles"
                :key="item.id"
                class="group relative overflow-hidden rounded-xl border border-gray-200 bg-white shadow-sm dark:border-gray-700 dark:bg-gray-800"
              >
                <img
                  v-if="item.previewUrl"
                  :src="item.previewUrl"
                  :alt="item.file.name"
                  class="aspect-square w-full object-cover"
                />
                <div
                  v-else
                  class="flex aspect-square flex-col items-center justify-center gap-1 bg-gray-100 px-2 text-center dark:bg-gray-900"
                >
                  <svg class="h-7 w-7 text-gray-400" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75">
                    <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
                    <path d="M14 2v6h6" />
                  </svg>
                  <span class="line-clamp-2 text-[10px] text-gray-500">{{ item.file.name }}</span>
                </div>
                <button
                  type="button"
                  class="absolute right-1.5 top-1.5 flex h-7 w-7 items-center justify-center rounded-full bg-black/60 text-white opacity-90 hover:bg-red-600"
                  title="Kaldır"
                  @click="removeFile(item.id)"
                >
                  <svg class="h-3.5 w-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
                    <path d="M18 6 6 18M6 6l12 12" />
                  </svg>
                </button>
                <p class="truncate px-2 py-1.5 text-[10px] text-gray-500">{{ item.file.name }}</p>
              </div>
            </div>
          </div>
        </div>

        <div class="grid gap-4 sm:grid-cols-2">
          <div>
            <label class="flex items-center gap-1.5">
              <svg class="h-3.5 w-3.5 text-blue-500" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <path d="M20.59 13.41l-7.17 7.17a2 2 0 0 1-2.83 0L2 12V2h10l8.59 8.59a2 2 0 0 1 0 2.82z" />
                <path d="M7 7h.01" />
              </svg>
              Kategori <span class="text-red-400">*</span>
            </label>
            <input
              v-model="category"
              required
              class="w-full"
              placeholder="Örn. Ağ, Elektrik, Temizlik"
            />
          </div>
          <div>
            <label class="flex items-center gap-1.5">
              <svg class="h-3.5 w-3.5 text-blue-500" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <path d="M3 21h18M5 21V7l7-4 7 4v14M9 21v-6h6v6" />
              </svg>
              Birim <span class="text-red-400">*</span>
            </label>
            <select v-model="departmentId" required class="w-full">
              <option :value="null" disabled>Birim seçin</option>
              <option v-for="d in departments" :key="d.id" :value="d.id">{{ d.name }}</option>
            </select>
          </div>
        </div>

        <div
          v-if="selectedDeptName"
          class="flex items-center gap-2 rounded-xl border border-teal-500/25 bg-teal-500/10 px-3.5 py-2.5 text-[12px] text-teal-700 dark:text-teal-300"
        >
          <svg class="h-4 w-4 shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M20 6 9 17l-5-5" />
          </svg>
          Talep <strong class="font-semibold">{{ selectedDeptName }}</strong> birimine yönlendirilecek.
        </div>

        <p
          v-if="error"
          class="rounded-xl border border-red-500/30 bg-red-500/10 px-3.5 py-2.5 text-[13px] text-red-700 dark:text-red-300"
        >
          {{ error }}
        </p>
        <p
          v-if="uploadWarning"
          class="rounded-xl border border-amber-500/30 bg-amber-500/10 px-3.5 py-2.5 text-[13px] text-amber-700 dark:text-amber-300"
        >
          {{ uploadWarning }}
        </p>
        <p
          v-if="success"
          class="rounded-xl border border-teal-500/30 bg-teal-500/10 px-3.5 py-2.5 text-[13px] text-teal-700 dark:text-teal-300"
        >
          {{ success }}
        </p>
      </div>

      <div
        class="flex flex-col-reverse gap-3 border-t border-gray-200/80 bg-slate-50/80 px-5 py-4 dark:border-gray-700/80 dark:bg-gray-900/40 sm:flex-row sm:items-center sm:justify-between md:px-6"
      >
        <p class="text-[11px] text-gray-500">
          {{ pendingFiles.length ? `${pendingFiles.length} ek seçildi · ` : '' }}
          Gönderim sonrası talebi “Taleplerim” üzerinden takip edebilirsiniz.
        </p>
        <button
          class="btn-primary min-w-[160px] px-6"
          type="submit"
          :disabled="!canSubmit"
        >
          <svg v-if="!loading" class="h-4 w-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M22 2 11 13M22 2l-7 20-4-9-9-4 20-7z" />
          </svg>
          {{ loading ? 'Gönderiliyor…' : 'Talebi Gönder' }}
        </button>
      </div>
    </form>
  </div>
</template>

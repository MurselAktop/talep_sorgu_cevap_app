<script setup lang="ts">
const { user, fetchProfile } = useAuth()
const supabase = useSupabase()

const ILLER = [
  'Adana', 'Adıyaman', 'Afyonkarahisar', 'Ağrı', 'Amasya', 'Ankara', 'Antalya', 'Artvin',
  'Aydın', 'Balıkesir', 'Bilecik', 'Bingöl', 'Bitlis', 'Bolu', 'Burdur', 'Bursa', 'Çanakkale',
  'Çankırı', 'Çorum', 'Denizli', 'Diyarbakır', 'Edirne', 'Elazığ', 'Erzincan', 'Erzurum',
  'Eskişehir', 'Gaziantep', 'Giresun', 'Gümüşhane', 'Hakkari', 'Hatay', 'Isparta', 'Mersin',
  'İstanbul', 'İzmir', 'Kars', 'Kastamonu', 'Kayseri', 'Kırklareli', 'Kırşehir', 'Kocaeli',
  'Konya', 'Kütahya', 'Malatya', 'Manisa', 'Kahramanmaraş', 'Mardin', 'Muğla', 'Muş',
  'Nevşehir', 'Niğde', 'Ordu', 'Rize', 'Sakarya', 'Samsun', 'Siirt', 'Sinop', 'Sivas',
  'Tekirdağ', 'Tokat', 'Trabzon', 'Tunceli', 'Şanlıurfa', 'Uşak', 'Van', 'Yozgat', 'Zonguldak',
  'Aksaray', 'Bayburt', 'Karaman', 'Kırıkkale', 'Batman', 'Şırnak', 'Bartın', 'Ardahan',
  'Iğdır', 'Yalova', 'Karabük', 'Kilis', 'Osmaniye', 'Düzce',
]

const form = reactive({
  full_name: user.value?.full_name || '',
  phone: user.value?.phone || '',
  il: user.value?.il || '',
  ilce: user.value?.ilce || '',
})
const message = ref('')
const messageTone = ref<'ok' | 'err'>('ok')
const avatarUrl = ref<string | null>(null)
const uploadingAvatar = ref(false)
const fileInput = ref<HTMLInputElement | null>(null)
const lightbox = ref<{ show: () => void } | null>(null)

async function loadAvatar() {
  avatarUrl.value = null
  const path = user.value?.avatar_url
  if (!path) return
  try {
    const { data } = await supabase.storage.from('avatars').createSignedUrl(path, 3600)
    avatarUrl.value = data?.signedUrl || null
  } catch {
    avatarUrl.value = null
  }
}

watch(
  () => user.value,
  (u) => {
    if (!u) return
    form.full_name = u.full_name || ''
    form.phone = u.phone || ''
    form.il = u.il || ''
    form.ilce = u.ilce || ''
    void loadAvatar()
  },
  { immediate: true },
)

const initials = computed(() => {
  const name = (user.value?.full_name || user.value?.email || '?').trim()
  const parts = name.split(/\s+/).filter(Boolean)
  if (parts.length >= 2) return (parts[0]![0]! + parts[1]![0]!).toUpperCase()
  return name.slice(0, 2).toUpperCase()
})

async function save() {
  message.value = ''
  const { error } = await supabase
    .from('users')
    .update({
      full_name: form.full_name.trim(),
      phone: form.phone.trim(),
      il: form.il,
      ilce: form.ilce.trim(),
    })
    .eq('id', user.value!.id)
  message.value = error ? error.message : 'Kaydedildi.'
  messageTone.value = error ? 'err' : 'ok'
  if (!error) await fetchProfile()
}

function guessMime(name: string) {
  const lower = name.toLowerCase()
  if (lower.endsWith('.png')) return 'image/png'
  if (lower.endsWith('.webp')) return 'image/webp'
  if (lower.endsWith('.gif')) return 'image/gif'
  return 'image/jpeg'
}

async function onAvatarPicked(e: Event) {
  const input = e.target as HTMLInputElement
  const file = input.files?.[0]
  input.value = ''
  if (!file || !user.value) return

  if (!file.type.startsWith('image/')) {
    message.value = 'Lütfen bir görsel dosyası seçin.'
    messageTone.value = 'err'
    return
  }
  if (file.size > 5 * 1024 * 1024) {
    message.value = 'Fotoğraf en fazla 5 MB olabilir.'
    messageTone.value = 'err'
    return
  }

  uploadingAvatar.value = true
  message.value = ''
  try {
    const storagePath = `${user.value.id}/avatar`
    const { error: upErr } = await supabase.storage.from('avatars').upload(storagePath, file, {
      upsert: true,
      contentType: file.type || guessMime(file.name),
    })
    if (upErr) throw upErr

    const { error: dbErr } = await supabase
      .from('users')
      .update({ avatar_url: storagePath })
      .eq('id', user.value.id)
    if (dbErr) throw dbErr

    await fetchProfile()
    await loadAvatar()
    message.value = 'Profil fotoğrafınız güncellendi.'
    messageTone.value = 'ok'
  } catch (err: any) {
    message.value = err?.message || 'Fotoğraf yüklenemedi. Lütfen tekrar deneyin.'
    messageTone.value = 'err'
  } finally {
    uploadingAvatar.value = false
  }
}
</script>

<template>
  <div>
    <PageHeader title="Profilim" subtitle="Hesap bilgilerinizi güncelleyin" />

    <p
      v-if="message"
      class="mb-4 rounded-xl px-4 py-2.5 text-[13px]"
      :class="messageTone === 'ok'
        ? 'border border-teal-500/30 bg-teal-500/10 text-teal-700 dark:text-teal-300'
        : 'border border-red-500/30 bg-red-500/10 text-red-700 dark:text-red-300'"
    >
      {{ message }}
    </p>

    <form class="card p-5 md:p-6" @submit.prevent="save">
      <div class="flex flex-col gap-6 lg:flex-row lg:items-start lg:gap-8">
        <!-- Sol: avatar -->
        <aside class="flex shrink-0 flex-col items-center gap-3 lg:w-52 lg:border-r lg:border-gray-200/70 lg:pr-8 dark:lg:border-gray-700/70">
          <div class="relative">
            <button
              type="button"
              class="flex h-28 w-28 cursor-zoom-in items-center justify-center overflow-hidden rounded-full border-2 border-white bg-gradient-to-b from-slate-100 to-slate-200 text-2xl font-semibold text-gray-600 shadow-puff transition hover:ring-2 hover:ring-blue-500/40 dark:border-gray-700 dark:from-gray-700 dark:to-gray-800 dark:text-gray-200 md:h-32 md:w-32"
              title="Büyüt"
              @click="avatarUrl ? lightbox?.show() : undefined"
            >
              <img v-if="avatarUrl" :src="avatarUrl" alt="Profil" class="h-full w-full object-cover" />
              <span v-else>{{ initials }}</span>
            </button>
            <button
              type="button"
              class="absolute -bottom-1 -right-1 flex h-9 w-9 items-center justify-center rounded-full border border-blue-400/40 bg-gradient-to-b from-blue-500 to-blue-600 text-white shadow-md hover:from-blue-400 hover:to-blue-500 disabled:opacity-60"
              :disabled="uploadingAvatar"
              title="Fotoğraf değiştir"
              @click.stop="fileInput?.click()"
            >
              <svg v-if="!uploadingAvatar" class="h-4 w-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <path d="M12 5v14M5 12h14" />
              </svg>
              <span v-else class="text-[10px]">…</span>
            </button>
            <input
              ref="fileInput"
              type="file"
              accept="image/jpeg,image/png,image/webp,image/gif"
              class="hidden"
              @change="onAvatarPicked"
            />
            <AvatarLightbox ref="lightbox" :src="avatarUrl" alt="Profil" />
          </div>
          <div class="text-center">
            <p class="text-[13px] font-semibold text-gray-900 dark:text-white">
              {{ user?.full_name || 'Kullanıcı' }}
            </p>
            <p class="text-[11px] text-gray-500">
              {{ roleLabels[user?.role || ''] || user?.role }}
            </p>
            <p class="mt-2 text-[11px] text-gray-400">
              {{ uploadingAvatar ? 'Yükleniyor…' : (avatarUrl ? 'Dokunarak büyütün · + ile değiştirin' : 'Fotoğraf eklemek için +') }}
            </p>
          </div>
        </aside>

        <!-- Sağ: form alanları yatay grid -->
        <div class="min-w-0 flex-1 space-y-4">
          <div class="grid gap-4 sm:grid-cols-2">
            <div>
              <label>E-posta (salt okunur)</label>
              <input :value="user?.email || ''" disabled class="w-full" />
            </div>
            <div>
              <label>Rol</label>
              <input :value="roleLabels[user?.role || ''] || user?.role" disabled class="w-full" />
            </div>
            <div>
              <label>Ad Soyad</label>
              <input v-model="form.full_name" required class="w-full" />
            </div>
            <div>
              <label>Telefon</label>
              <input v-model="form.phone" class="w-full" />
            </div>
            <div>
              <label>İl</label>
              <select v-model="form.il" class="w-full">
                <option value="">Seçin</option>
                <option v-for="il in ILLER" :key="il" :value="il">{{ il }}</option>
              </select>
            </div>
            <div>
              <label>İlçe</label>
              <input v-model="form.ilce" class="w-full" />
            </div>
          </div>

          <div class="flex justify-end pt-2">
            <button class="btn-primary min-w-[140px]" type="submit">Kaydet</button>
          </div>
        </div>
      </div>
    </form>
  </div>
</template>

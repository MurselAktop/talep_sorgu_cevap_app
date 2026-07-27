<script setup lang="ts">
definePageMeta({ layout: 'auth' })

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

const { signUp, checkRegistrationAvailability } = useAuth()

const form = reactive({
  fullName: '',
  email: '',
  password: '',
  tcNo: '',
  phone: '',
  il: '',
  ilce: '',
})
const loading = ref(false)
const error = ref('')
const fieldError = ref('')

function normalizePhone(raw: string) {
  const digits = raw.replace(/\D/g, '')
  if (digits.startsWith('90') && digits.length === 12) return `+${digits}`
  if (digits.startsWith('0') && digits.length === 11) return `+9${digits}`
  if (digits.length === 10) return `+90${digits}`
  return raw
}

async function submit() {
  error.value = ''
  fieldError.value = ''
  loading.value = true
  try {
    await checkRegistrationAvailability(form.tcNo.trim())
    await signUp({
      email: form.email.trim(),
      password: form.password,
      fullName: form.fullName.trim(),
      tcNo: form.tcNo.trim(),
      phone: normalizePhone(form.phone),
      il: form.il,
      ilce: form.ilce.trim(),
    })
    await navigateTo('/login')
  } catch (e: any) {
    const msg = e?.message || 'Kayıt başarısız.'
    if (msg.toLowerCase().includes('already') || msg.includes('e-posta')) error.value = msg
    else fieldError.value = msg
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="card space-y-6 p-8 sm:p-9">
    <div class="text-center">
      <div
        class="mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-2xl bg-gradient-to-b from-emerald-500 to-emerald-700 text-white shadow-[0_8px_20px_rgba(16,185,129,0.3)]"
      >
        <svg class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.8">
          <path stroke-linecap="round" stroke-linejoin="round" d="M19 7.5v3m0 0v3m0-3h3m-3 0h-3m-2.25-4.125a3.375 3.375 0 11-6.75 0 3.375 3.375 0 016.75 0zM4 19.235v-.11a6.375 6.375 0 0112.75 0v.109A12.318 12.318 0 0110.374 21c-2.331 0-4.512-.645-6.374-1.766z" />
        </svg>
      </div>
      <h1 class="text-2xl font-bold tracking-tight text-gray-900 dark:text-white">Vatandaş Kaydı</h1>
      <p class="mt-1.5 text-sm text-gray-500 dark:text-gray-400">Hesap oluşturup taleplerinizi takip edin</p>
    </div>

    <form class="space-y-4" @submit.prevent="submit">
      <div class="grid gap-4 sm:grid-cols-2">
        <div class="sm:col-span-2">
          <label>Ad Soyad</label>
          <input v-model="form.fullName" required placeholder="Adınız Soyadınız" />
        </div>
        <div class="sm:col-span-2">
          <label>E-posta</label>
          <input v-model="form.email" type="email" required placeholder="ornek@email.com" />
        </div>
        <div class="sm:col-span-2">
          <label>Şifre</label>
          <input v-model="form.password" type="password" required minlength="6" placeholder="En az 6 karakter" />
        </div>
        <div>
          <label>T.C. Kimlik No</label>
          <input v-model="form.tcNo" required maxlength="11" inputmode="numeric" placeholder="11 haneli" />
        </div>
        <div>
          <label>Telefon</label>
          <input v-model="form.phone" required placeholder="5XX XXX XX XX" />
        </div>
        <div>
          <label>İl</label>
          <select v-model="form.il" required>
            <option value="" disabled>Seçin</option>
            <option v-for="il in ILLER" :key="il" :value="il">{{ il }}</option>
          </select>
        </div>
        <div>
          <label>İlçe</label>
          <input v-model="form.ilce" required placeholder="İlçe" />
        </div>
      </div>

      <p
        v-if="fieldError || error"
        class="rounded-xl border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700 dark:border-red-500/30 dark:bg-red-500/10 dark:text-red-300"
      >
        {{ fieldError || error }}
      </p>

      <button class="btn-primary w-full py-3" type="submit" :disabled="loading">
        {{ loading ? 'Kaydediliyor…' : 'Kayıt Ol' }}
      </button>

      <NuxtLink
        to="/login"
        class="block text-center text-sm text-gray-500 transition hover:text-blue-600 dark:text-gray-400 dark:hover:text-blue-300"
      >
        ← Girişe dön
      </NuxtLink>
    </form>
  </div>
</template>

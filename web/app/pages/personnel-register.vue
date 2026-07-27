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
  inviteCode: '',
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

function normalizePhone(raw: string) {
  const digits = raw.replace(/\D/g, '')
  if (digits.startsWith('90') && digits.length === 12) return `+${digits}`
  if (digits.startsWith('0') && digits.length === 11) return `+9${digits}`
  if (digits.length === 10) return `+90${digits}`
  return raw
}

async function submit() {
  error.value = ''
  loading.value = true
  try {
    const code = form.inviteCode.trim().toUpperCase()
    await checkRegistrationAvailability(form.tcNo.trim(), code)
    await signUp({
      email: form.email.trim(),
      password: form.password,
      fullName: form.fullName.trim(),
      tcNo: form.tcNo.trim(),
      phone: normalizePhone(form.phone),
      il: form.il,
      ilce: form.ilce.trim(),
      inviteCode: code,
    })
    await navigateTo('/login')
  } catch (e: any) {
    error.value = e?.message || 'Kayıt başarısız.'
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="card space-y-6 p-8 sm:p-9">
    <div class="text-center">
      <div
        class="mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-2xl bg-gradient-to-b from-blue-500 to-blue-700 text-white shadow-[0_8px_20px_rgba(37,99,235,0.3)]"
      >
        <svg class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.8">
          <path stroke-linecap="round" stroke-linejoin="round" d="M2.25 21h19.5M3.75 3h16.5v12.75A2.25 2.25 0 0118 18H6a2.25 2.25 0 01-2.25-2.25V3z" />
        </svg>
      </div>
      <h1 class="text-2xl font-bold tracking-tight text-gray-900 dark:text-white">Personel Kaydı</h1>
      <p class="mt-1.5 text-sm text-gray-500 dark:text-gray-400">Davet kodu ile kurum hesabı oluşturun</p>
    </div>

    <form class="space-y-4" @submit.prevent="submit">
      <div class="grid gap-4 sm:grid-cols-2">
        <div class="sm:col-span-2">
          <label>Davet Kodu</label>
          <input v-model="form.inviteCode" required class="uppercase tracking-wider" placeholder="Davet kodunuz" />
        </div>
        <div class="sm:col-span-2">
          <label>Ad Soyad</label>
          <input v-model="form.fullName" required placeholder="Adınız Soyadınız" />
        </div>
        <div class="sm:col-span-2">
          <label>E-posta</label>
          <input v-model="form.email" type="email" required placeholder="ornek@kurum.gov.tr" />
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
        v-if="error"
        class="rounded-xl border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700 dark:border-red-500/30 dark:bg-red-500/10 dark:text-red-300"
      >
        {{ error }}
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

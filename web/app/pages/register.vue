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
  <div class="card space-y-4">
    <div class="text-center">
      <p class="text-2xl font-bold text-blue-400">Vatandaş Kaydı</p>
    </div>
    <form class="space-y-3" @submit.prevent="submit">
      <div>
        <label>Ad Soyad</label>
        <input v-model="form.fullName" required class="w-full" />
      </div>
      <div>
        <label>E-posta</label>
        <input v-model="form.email" type="email" required class="w-full" />
      </div>
      <div>
        <label>Şifre</label>
        <input v-model="form.password" type="password" required minlength="6" class="w-full" />
      </div>
      <div>
        <label>T.C. Kimlik No</label>
        <input v-model="form.tcNo" required maxlength="11" class="w-full" />
      </div>
      <div>
        <label>Telefon</label>
        <input v-model="form.phone" required placeholder="5XX XXX XX XX" class="w-full" />
      </div>
      <div>
        <label>İl</label>
        <select v-model="form.il" required class="w-full">
          <option value="" disabled>Seçin</option>
          <option v-for="il in ILLER" :key="il" :value="il">{{ il }}</option>
        </select>
      </div>
      <div>
        <label>İlçe</label>
        <input v-model="form.ilce" required class="w-full" />
      </div>

      <p v-if="fieldError" class="text-sm text-status-reddedildi">{{ fieldError }}</p>
      <p v-if="error" class="text-sm text-status-reddedildi">{{ error }}</p>

      <button class="btn-primary w-full" type="submit" :disabled="loading">
        {{ loading ? 'Kaydediliyor…' : 'Kayıt Ol' }}
      </button>
      <NuxtLink to="/login" class="block text-center text-sm text-white/60 hover:text-white">
        Girişe dön
      </NuxtLink>
    </form>
  </div>
</template>

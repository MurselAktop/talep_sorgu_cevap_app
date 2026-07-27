<script setup lang="ts">
definePageMeta({ layout: 'auth' })

const { signIn, user } = useAuth()

type LoginType = 'vatandas' | 'personel' | null
const selected = ref<LoginType>(null)
const email = ref('')
const password = ref('')
const remember = ref(false)
const loading = ref(false)
const error = ref('')
const showPassword = ref(false)

async function submit() {
  error.value = ''
  loading.value = true
  try {
    await signIn(email.value.trim(), password.value)
    const profile = user.value
    if (!profile) throw new Error('Profil bulunamadı.')

    const expectedVatandas = selected.value === 'vatandas'
    const isVatandasAccount = profile.role === 'vatandas'
    if (isVatandasAccount !== expectedVatandas) {
      await useSupabase().auth.signOut()
      error.value = expectedVatandas
        ? 'Giriş bilgileri hatalı. Böyle bir vatandaş hesabı bulunamadı.'
        : 'Giriş bilgileri hatalı. Böyle bir personel hesabı bulunamadı.'
      return
    }

    if (remember.value) {
      localStorage.setItem('tsys_remember_me', '1')
    } else {
      localStorage.removeItem('tsys_remember_me')
    }

    await navigateTo('/home')
  } catch (e: any) {
    error.value = e?.message?.includes('Invalid login')
      ? 'E-posta veya şifre hatalı.'
      : e?.message || 'Giriş yapılamadı.'
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="card space-y-5">
    <div class="text-center">
      <p class="text-3xl font-bold text-blue-600 dark:text-blue-400">TŞYS</p>
      <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">Talep ve Şikâyet Yönetim Sistemi</p>
    </div>

    <div v-if="!selected" class="space-y-3">
      <button class="btn-primary w-full" type="button" @click="selected = 'vatandas'">
        Vatandaş Girişi
      </button>
      <button class="btn-secondary w-full" type="button" @click="selected = 'personel'">
        Personel Girişi
      </button>
      <NuxtLink to="/guest" class="btn-secondary w-full">
        Giriş Yapmadan Devam Et
      </NuxtLink>
    </div>

    <form v-else class="space-y-4" @submit.prevent="submit">
      <button
        class="text-sm text-gray-500 transition-all duration-200 hover:text-gray-800 dark:text-gray-400 dark:hover:text-white"
        type="button"
        @click="selected = null"
      >
        ← Geri
      </button>
      <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
        {{ selected === 'vatandas' ? 'Vatandaş Girişi' : 'Personel Girişi' }}
      </h2>

      <div>
        <label>E-posta</label>
        <input v-model="email" type="email" required autocomplete="username" />
      </div>
      <div>
        <label>Şifre</label>
        <div class="relative">
          <input
            v-model="password"
            :type="showPassword ? 'text' : 'password'"
            required
            autocomplete="current-password"
            class="pr-20"
          />
          <button
            class="absolute right-2 top-1/2 -translate-y-1/2 text-xs text-gray-500 transition-all duration-200 hover:text-gray-800 dark:hover:text-gray-200"
            type="button"
            @click="showPassword = !showPassword"
          >
            {{ showPassword ? 'Gizle' : 'Göster' }}
          </button>
        </div>
      </div>

      <label class="flex items-center gap-2 text-sm font-normal text-gray-600 dark:text-gray-300">
        <input v-model="remember" type="checkbox" class="h-4 w-4 rounded border-gray-300" />
        Beni Hatırla
      </label>

      <p v-if="error" class="text-sm text-red-600 dark:text-red-400">{{ error }}</p>

      <button class="btn-primary w-full" type="submit" :disabled="loading">
        {{ loading ? 'Giriş yapılıyor…' : 'Giriş Yap' }}
      </button>

      <div class="space-y-2 text-center text-sm text-gray-500 dark:text-gray-400">
        <NuxtLink to="/forgot-password" class="block transition-all duration-200 hover:text-blue-600 dark:text-blue-400">
          Şifremi unuttum
        </NuxtLink>
        <NuxtLink
          v-if="selected === 'vatandas'"
          to="/register"
          class="block transition-all duration-200 hover:text-blue-600 dark:text-blue-400"
        >
          Hesap oluştur
        </NuxtLink>
        <NuxtLink
          v-else
          to="/personnel-register"
          class="block transition-all duration-200 hover:text-blue-600 dark:text-blue-400"
        >
          Davet kodu ile kayıt ol
        </NuxtLink>
      </div>
    </form>
  </div>
</template>

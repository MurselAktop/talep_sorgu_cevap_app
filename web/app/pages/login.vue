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
  <div class="card space-y-7 p-8 sm:p-9">
    <!-- Brand -->
    <div class="text-center">
      <div
        class="mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-2xl bg-gradient-to-b from-blue-500 to-blue-700 text-sm font-bold text-white shadow-[0_8px_20px_rgba(37,99,235,0.35)]"
      >
        TŞ
      </div>
      <h1 class="text-3xl font-bold tracking-tight text-blue-600 dark:text-blue-400">TŞYS</h1>
      <p class="mt-1.5 text-sm text-gray-500 dark:text-gray-400">
        Talep ve Şikâyet Yönetim Sistemi
      </p>
    </div>

    <!-- Type picker -->
    <div v-if="!selected" class="space-y-3">
      <p class="text-center text-xs font-medium uppercase tracking-wider text-gray-400">
        Giriş türü seçin
      </p>

      <button
        class="group flex w-full items-center gap-3 rounded-2xl border border-gray-200/90 bg-white/80 px-4 py-3.5 text-left transition-all duration-200 hover:border-blue-300 hover:bg-blue-50/60 dark:border-gray-600 dark:bg-gray-800/60 dark:hover:border-blue-500/50 dark:hover:bg-blue-500/10"
        type="button"
        @click="selected = 'vatandas'"
      >
        <span
          class="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-emerald-500/15 text-emerald-600 dark:text-emerald-400"
        >
          <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.8">
            <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 6a3.75 3.75 0 11-7.5 0 3.75 3.75 0 017.5 0zM4.5 20.25a8.25 8.25 0 0115 0" />
          </svg>
        </span>
        <span class="min-w-0 flex-1">
          <span class="block text-sm font-semibold text-gray-900 dark:text-white">Vatandaş Girişi</span>
          <span class="block text-xs text-gray-500 dark:text-gray-400">Hesabınızla talep takip edin</span>
        </span>
        <span class="text-gray-300 transition group-hover:text-blue-500 dark:text-gray-600">→</span>
      </button>

      <button
        class="group flex w-full items-center gap-3 rounded-2xl border border-gray-200/90 bg-white/80 px-4 py-3.5 text-left transition-all duration-200 hover:border-blue-300 hover:bg-blue-50/60 dark:border-gray-600 dark:bg-gray-800/60 dark:hover:border-blue-500/50 dark:hover:bg-blue-500/10"
        type="button"
        @click="selected = 'personel'"
      >
        <span
          class="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-blue-500/15 text-blue-600 dark:text-blue-400"
        >
          <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.8">
            <path stroke-linecap="round" stroke-linejoin="round" d="M2.25 21h19.5M3.75 3h16.5v12.75A2.25 2.25 0 0118 18H6a2.25 2.25 0 01-2.25-2.25V3z" />
          </svg>
        </span>
        <span class="min-w-0 flex-1">
          <span class="block text-sm font-semibold text-gray-900 dark:text-white">Personel Girişi</span>
          <span class="block text-xs text-gray-500 dark:text-gray-400">Personel, müdür veya admin</span>
        </span>
        <span class="text-gray-300 transition group-hover:text-blue-500 dark:text-gray-600">→</span>
      </button>

      <NuxtLink
        to="/guest"
        class="flex w-full items-center justify-center rounded-2xl border border-dashed border-gray-300 px-4 py-3 text-sm font-medium text-gray-600 transition hover:border-gray-400 hover:bg-white/50 dark:border-gray-600 dark:text-gray-300 dark:hover:bg-gray-800/40"
      >
        Giriş Yapmadan Devam Et
      </NuxtLink>
    </div>

    <!-- Credentials form -->
    <form v-else class="space-y-5" @submit.prevent="submit">
      <div class="flex items-center justify-between gap-3">
        <button
          class="text-sm text-gray-500 transition hover:text-gray-800 dark:text-gray-400 dark:hover:text-white"
          type="button"
          @click="selected = null"
        >
          ← Geri
        </button>
        <span
          class="rounded-full bg-blue-500/10 px-3 py-1 text-xs font-medium text-blue-600 dark:text-blue-300"
        >
          {{ selected === 'vatandas' ? 'Vatandaş' : 'Personel' }}
        </span>
      </div>

      <div>
        <h2 class="text-xl font-semibold tracking-tight text-gray-900 dark:text-white">
          {{ selected === 'vatandas' ? 'Vatandaş Girişi' : 'Personel Girişi' }}
        </h2>
        <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
          E-posta ve şifrenizle devam edin
        </p>
      </div>

      <div class="space-y-4">
        <div>
          <label for="login-email">E-posta</label>
          <input
            id="login-email"
            v-model="email"
            type="email"
            required
            autocomplete="username"
            placeholder="ornek@kurum.gov.tr"
          />
        </div>

        <div>
          <label for="login-password">Şifre</label>
          <div class="relative">
            <input
              id="login-password"
              v-model="password"
              :type="showPassword ? 'text' : 'password'"
              required
              autocomplete="current-password"
              placeholder="••••••••"
              class="pr-16"
            />
            <button
              class="absolute inset-y-0 right-0 flex items-center px-3 text-xs font-medium text-gray-500 transition hover:text-blue-600 dark:text-gray-400 dark:hover:text-blue-300"
              type="button"
              @click="showPassword = !showPassword"
            >
              {{ showPassword ? 'Gizle' : 'Göster' }}
            </button>
          </div>
        </div>
      </div>

      <label class="flex cursor-pointer items-center gap-2.5 text-sm font-normal text-gray-600 dark:text-gray-300">
        <input
          v-model="remember"
          type="checkbox"
          class="h-4 w-4 rounded border-gray-300 text-blue-600 focus:ring-blue-500/30 dark:border-gray-500 dark:bg-gray-800"
        />
        Beni Hatırla
      </label>

      <p
        v-if="error"
        class="rounded-xl border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700 dark:border-red-500/30 dark:bg-red-500/10 dark:text-red-300"
      >
        {{ error }}
      </p>

      <button class="btn-primary w-full py-3" type="submit" :disabled="loading">
        {{ loading ? 'Giriş yapılıyor…' : 'Giriş Yap' }}
      </button>

      <div class="flex flex-col items-center gap-2 border-t border-gray-100 pt-4 text-sm dark:border-gray-700/80">
        <NuxtLink
          to="/forgot-password"
          class="text-gray-500 transition hover:text-blue-600 dark:text-gray-400 dark:hover:text-blue-300"
        >
          Şifremi unuttum
        </NuxtLink>
        <NuxtLink
          v-if="selected === 'vatandas'"
          to="/register"
          class="font-medium text-blue-600 transition hover:text-blue-500 dark:text-blue-400"
        >
          Hesap oluştur
        </NuxtLink>
        <NuxtLink
          v-else
          to="/personnel-register"
          class="font-medium text-blue-600 transition hover:text-blue-500 dark:text-blue-400"
        >
          Davet kodu ile kayıt ol
        </NuxtLink>
      </div>
    </form>
  </div>
</template>

<script setup lang="ts">
const supabase = useSupabase()
const { isDark, toggle, apply } = useTheme()

const currentPassword = ref('')
const newPassword = ref('')
const message = ref('')
const loading = ref(false)

async function changePassword() {
  message.value = ''
  loading.value = true
  try {
    const email = (await supabase.auth.getUser()).data.user?.email
    if (!email) throw new Error('Oturum yok.')
    const { error: signErr } = await supabase.auth.signInWithPassword({
      email,
      password: currentPassword.value,
    })
    if (signErr) throw new Error('Mevcut şifre hatalı.')
    const { error } = await supabase.auth.updateUser({ password: newPassword.value })
    if (error) throw error
    message.value = 'Şifre güncellendi.'
    currentPassword.value = ''
    newPassword.value = ''
  } catch (e: any) {
    message.value = e?.message || 'İşlem başarısız.'
  } finally {
    loading.value = false
  }
}

function onThemeSwitch(e: Event) {
  const checked = (e.target as HTMLInputElement).checked
  apply(checked ? 'dark' : 'light')
}
</script>

<template>
  <div class="mx-auto max-w-2xl space-y-5">
    <PageHeader title="Sistem Ayarları" subtitle="Hesap güvenliği ve görünüm tercihleri" />

    <!-- Theme card -->
    <div class="card p-5 shadow-sm">
      <div class="flex items-start gap-4">
        <div class="rounded-xl bg-blue-500/15 p-3 text-blue-600 dark:text-blue-400">
          <svg class="h-6 w-6" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75">
            <circle cx="12" cy="12" r="4" />
            <path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4" />
          </svg>
        </div>
        <div class="min-w-0 flex-1">
          <h2 class="font-semibold text-gray-900 dark:text-white">Tema</h2>
          <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
            Açık tema göz yormayan kırık beyaz arka plan kullanır. Koyu tema uzun oturumlar için uygundur.
          </p>
          <label class="mt-4 flex cursor-pointer items-center justify-between gap-4 rounded-xl border border-gray-200 bg-slate-50 px-4 py-3 dark:border-gray-700 dark:bg-gray-900">
            <span class="text-sm font-medium text-gray-800 dark:text-gray-100">
              {{ isDark ? 'Koyu mod açık' : 'Açık mod açık' }}
            </span>
            <input
              type="checkbox"
              class="peer sr-only"
              :checked="isDark"
              @change="onThemeSwitch"
            />
            <span
              class="relative h-7 w-12 rounded-full bg-gray-300 transition-colors peer-checked:bg-blue-600 dark:bg-gray-600"
            >
              <span
                class="absolute left-0.5 top-0.5 h-6 w-6 rounded-full bg-white transition-transform"
                :class="isDark ? 'translate-x-5' : ''"
              />
            </span>
          </label>
          <div class="mt-3 flex gap-2">
            <button type="button" class="btn-secondary text-xs" @click="apply('light')">Açık</button>
            <button type="button" class="btn-secondary text-xs" @click="apply('dark')">Koyu</button>
            <button type="button" class="btn-secondary text-xs" @click="toggle">Değiştir</button>
          </div>
        </div>
      </div>
    </div>

    <!-- Password card -->
    <form class="card space-y-4 p-5 shadow-sm" @submit.prevent="changePassword">
      <div class="flex items-start gap-4">
        <div class="rounded-xl bg-amber-500/15 p-3 text-amber-600 dark:text-amber-400">
          <svg class="h-6 w-6" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75">
            <rect x="5" y="11" width="14" height="10" rx="2" />
            <path d="M8 11V8a4 4 0 0 1 8 0v3" />
          </svg>
        </div>
        <div class="min-w-0 flex-1">
          <h2 class="font-semibold text-gray-900 dark:text-white">Şifre Değiştir</h2>
          <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
            Güvenliğiniz için mevcut şifrenizi doğruladıktan sonra yeni şifre belirlenir.
          </p>
        </div>
      </div>
      <div>
        <label>Mevcut şifre</label>
        <input v-model="currentPassword" type="password" required autocomplete="current-password" />
      </div>
      <div>
        <label>Yeni şifre</label>
        <input v-model="newPassword" type="password" required minlength="6" autocomplete="new-password" />
      </div>
      <p v-if="message" class="text-sm text-blue-600 dark:text-blue-400">{{ message }}</p>
      <button class="btn-primary" type="submit" :disabled="loading">
        {{ loading ? 'Güncelleniyor…' : 'Şifreyi Güncelle' }}
      </button>
    </form>
  </div>
</template>

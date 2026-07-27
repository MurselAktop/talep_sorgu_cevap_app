<script setup lang="ts">
definePageMeta({ layout: 'auth' })

const supabase = useSupabase()
const email = ref('')
const message = ref('')
const isError = ref(false)
const loading = ref(false)

async function submit() {
  message.value = ''
  isError.value = false
  loading.value = true
  try {
    const { error } = await supabase.auth.resetPasswordForEmail(email.value.trim())
    if (error) throw error
    message.value = 'Şifre sıfırlama e-postası gönderildi. Gelen kutunuzu kontrol edin.'
  } catch (e: any) {
    isError.value = true
    message.value = e?.message || 'Gönderilemedi.'
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
          <path stroke-linecap="round" stroke-linejoin="round" d="M16.5 10.5V6.75a4.5 4.5 0 10-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 002.25-2.25v-6.75a2.25 2.25 0 00-2.25-2.25H6.75a2.25 2.25 0 00-2.25 2.25v6.75a2.25 2.25 0 002.25 2.25z" />
        </svg>
      </div>
      <h1 class="text-2xl font-bold tracking-tight text-gray-900 dark:text-white">Şifremi Unuttum</h1>
      <p class="mt-1.5 text-sm text-gray-500 dark:text-gray-400">
        E-posta adresinize sıfırlama bağlantısı / kodu gönderilir
      </p>
    </div>

    <form class="space-y-4" @submit.prevent="submit">
      <div>
        <label>E-posta</label>
        <input v-model="email" type="email" required placeholder="hesap@email.com" />
      </div>

      <p
        v-if="message"
        class="rounded-xl border px-3 py-2 text-sm"
        :class="
          isError
            ? 'border-red-200 bg-red-50 text-red-700 dark:border-red-500/30 dark:bg-red-500/10 dark:text-red-300'
            : 'border-emerald-200 bg-emerald-50 text-emerald-800 dark:border-emerald-500/30 dark:bg-emerald-500/10 dark:text-emerald-300'
        "
      >
        {{ message }}
      </p>

      <button class="btn-primary w-full py-3" type="submit" :disabled="loading">
        {{ loading ? 'Gönderiliyor…' : 'Gönder' }}
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

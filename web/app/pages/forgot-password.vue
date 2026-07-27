<script setup lang="ts">
definePageMeta({ layout: 'auth' })

const supabase = useSupabase()
const email = ref('')
const message = ref('')
const loading = ref(false)

async function submit() {
  message.value = ''
  loading.value = true
  try {
    const { error } = await supabase.auth.resetPasswordForEmail(email.value.trim())
    if (error) throw error
    message.value = 'Şifre sıfırlama e-postası gönderildi (gerçek SMTP / Cloud mailer).'
  } catch (e: any) {
    message.value = e?.message || 'Gönderilemedi.'
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="card space-y-4">
    <h1 class="text-xl font-semibold text-center">Şifremi Unuttum</h1>
    <form class="space-y-3" @submit.prevent="submit">
      <div>
        <label>E-posta</label>
        <input v-model="email" type="email" required class="w-full" />
      </div>
      <p v-if="message" class="text-sm text-blue-400">{{ message }}</p>
      <button class="btn-primary w-full" type="submit" :disabled="loading">Gönder</button>
      <NuxtLink to="/login" class="block text-center text-sm text-white/60">Girişe dön</NuxtLink>
    </form>
  </div>
</template>

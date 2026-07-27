<script setup lang="ts">
definePageMeta({ layout: 'auth' })
</script>

<template>
  <div class="card space-y-4 text-center">
    <p class="text-2xl font-bold text-blue-400">Misafir Menü</p>
    <p class="text-sm text-white/50">Giriş yapmadan devam edin</p>
    <NuxtLink to="/guest/create" class="btn-primary w-full">Talep Oluştur</NuxtLink>
    <NuxtLink to="/guest/query" class="btn-secondary w-full">Sonucu Sorgula</NuxtLink>
    <NuxtLink to="/login" class="text-sm text-white/60 hover:text-white">Girişe dön</NuxtLink>
  </div>
</template>

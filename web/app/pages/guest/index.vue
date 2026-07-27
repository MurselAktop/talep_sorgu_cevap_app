<script setup lang="ts">
definePageMeta({ layout: 'auth' })
</script>

<template>
  <div class="card space-y-7 p-8 sm:p-9">
    <div class="text-center">
      <div
        class="mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-2xl bg-gradient-to-b from-slate-500 to-slate-700 text-white shadow-lg"
      >
        <svg class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.8">
          <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 6a3.75 3.75 0 11-7.5 0 3.75 3.75 0 017.5 0zM4.5 20.25a8.25 8.25 0 0115 0" />
        </svg>
      </div>
      <h1 class="text-2xl font-bold tracking-tight text-gray-900 dark:text-white">Misafir Menü</h1>
      <p class="mt-1.5 text-sm text-gray-500 dark:text-gray-400">
        Hesap açmadan talep oluşturun veya sonucunuzu sorgulayın
      </p>
    </div>

    <div class="space-y-3">
      <NuxtLink
        to="/guest/create"
        class="group flex w-full items-center gap-3 rounded-2xl border border-gray-200/90 bg-white/80 px-4 py-3.5 text-left transition-all duration-200 hover:border-blue-300 hover:bg-blue-50/60 dark:border-gray-600 dark:bg-gray-800/60 dark:hover:border-blue-500/50 dark:hover:bg-blue-500/10"
      >
        <span
          class="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-amber-500/15 text-amber-600 dark:text-amber-400"
        >
          <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.8">
            <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
          </svg>
        </span>
        <span class="min-w-0 flex-1">
          <span class="block text-sm font-semibold text-gray-900 dark:text-white">Talep Oluştur</span>
          <span class="block text-xs text-gray-500 dark:text-gray-400">Anonim talep açın, kod alın</span>
        </span>
        <span class="text-gray-300 transition group-hover:text-blue-500 dark:text-gray-600">→</span>
      </NuxtLink>

      <NuxtLink
        to="/guest/query"
        class="group flex w-full items-center gap-3 rounded-2xl border border-gray-200/90 bg-white/80 px-4 py-3.5 text-left transition-all duration-200 hover:border-blue-300 hover:bg-blue-50/60 dark:border-gray-600 dark:bg-gray-800/60 dark:hover:border-blue-500/50 dark:hover:bg-blue-500/10"
      >
        <span
          class="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-sky-500/15 text-sky-600 dark:text-sky-400"
        >
          <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.8">
            <path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-5.197-5.197m0 0A7.5 7.5 0 105.196 5.196a7.5 7.5 0 0010.607 10.607z" />
          </svg>
        </span>
        <span class="min-w-0 flex-1">
          <span class="block text-sm font-semibold text-gray-900 dark:text-white">Sonucu Sorgula</span>
          <span class="block text-xs text-gray-500 dark:text-gray-400">Erişim kodunuzla durumu görün</span>
        </span>
        <span class="text-gray-300 transition group-hover:text-blue-500 dark:text-gray-600">→</span>
      </NuxtLink>
    </div>

    <NuxtLink
      to="/login"
      class="block text-center text-sm text-gray-500 transition hover:text-blue-600 dark:text-gray-400 dark:hover:text-blue-300"
    >
      ← Girişe dön
    </NuxtLink>
  </div>
</template>

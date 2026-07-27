<script setup lang="ts">
const { user, signOut, fetchProfile } = useAuth()
const supabase = useSupabase()
const open = ref(false)
const root = ref<HTMLElement | null>(null)
const avatarUrl = ref<string | null>(null)
const departmentName = ref('—')
const lightbox = ref<{ show: () => void } | null>(null)

const initials = computed(() => {
  const name = user.value?.full_name?.trim() || '?'
  const parts = name.split(/\s+/).filter(Boolean)
  if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase()
  return name.slice(0, 2).toUpperCase()
})

async function loadExtras() {
  if (!user.value) return
  avatarUrl.value = null
  departmentName.value = '—'

  if (user.value.avatar_url) {
    try {
      const { data } = await supabase.storage.from('avatars').createSignedUrl(user.value.avatar_url, 3600)
      avatarUrl.value = data?.signedUrl || null
    } catch {
      avatarUrl.value = null
    }
  }

  if (user.value.department_id != null) {
    const { data } = await supabase
      .from('departments')
      .select('name')
      .eq('id', user.value.department_id)
      .maybeSingle()
    departmentName.value = data?.name || '—'
  }
}

watch(
  () => [user.value?.id, user.value?.avatar_url, user.value?.department_id],
  () => {
    void loadExtras()
  },
  { immediate: true },
)

function onDocClick(e: MouseEvent) {
  if (!root.value?.contains(e.target as Node)) open.value = false
}

async function logout() {
  open.value = false
  await signOut()
  await navigateTo('/login')
}

async function openMenu() {
  open.value = !open.value
  if (open.value) {
    await fetchProfile()
    await loadExtras()
  }
}

onMounted(() => document.addEventListener('click', onDocClick))
onUnmounted(() => document.removeEventListener('click', onDocClick))
</script>

<template>
  <div ref="root" class="relative">
    <button
      type="button"
      class="flex items-center gap-2 rounded-lg px-1.5 py-1 hover:bg-gray-200/70 dark:hover:bg-gray-700"
      aria-haspopup="menu"
      :aria-expanded="open"
      @click.stop="openMenu"
    >
      <img
        v-if="avatarUrl"
        :src="avatarUrl"
        alt=""
        class="h-8 w-8 rounded-full object-cover"
      />
      <span
        v-else
        class="flex h-8 w-8 items-center justify-center rounded-full bg-blue-600 text-xs font-semibold text-white"
      >
        {{ initials }}
      </span>
      <span class="hidden max-w-[140px] truncate text-[13px] font-medium text-gray-800 dark:text-gray-100 sm:block">
        {{ user?.full_name || 'Kullanıcı' }}
      </span>
      <svg class="hidden h-4 w-4 text-gray-400 sm:block" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <path d="M6 9l6 6 6-6" />
      </svg>
    </button>

    <div
      v-if="open"
      class="absolute right-0 z-50 mt-2 w-80 overflow-hidden rounded-xl border border-gray-200 bg-slate-50 shadow-lg dark:border-gray-700 dark:bg-gray-800"
      role="menu"
    >
      <div class="flex items-center gap-3 border-b border-gray-200 px-4 py-4 dark:border-gray-700">
        <button
          v-if="avatarUrl"
          type="button"
          class="shrink-0 cursor-zoom-in overflow-hidden rounded-full ring-2 ring-transparent transition hover:ring-blue-500/50"
          title="Büyüt"
          @click.stop="lightbox?.show()"
        >
          <img :src="avatarUrl" alt="" class="h-12 w-12 object-cover" />
        </button>
        <span
          v-else
          class="flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-blue-600 text-sm font-semibold text-white"
        >
          {{ initials }}
        </span>
        <div class="min-w-0">
          <p class="truncate font-semibold text-gray-900 dark:text-white">{{ user?.full_name || '—' }}</p>
          <p class="truncate text-xs text-gray-500 dark:text-gray-400">
            {{ roleLabels[user?.role || ''] || user?.role }}
          </p>
        </div>
      </div>

      <dl class="space-y-2 px-4 py-3 text-sm">
        <div>
          <dt class="text-xs text-gray-500 dark:text-gray-400">E-posta</dt>
          <dd class="truncate text-gray-800 dark:text-gray-100">{{ user?.email || '—' }}</dd>
        </div>
        <div>
          <dt class="text-xs text-gray-500 dark:text-gray-400">Telefon</dt>
          <dd class="text-gray-800 dark:text-gray-100">{{ user?.phone || '—' }}</dd>
        </div>
        <div>
          <dt class="text-xs text-gray-500 dark:text-gray-400">İl / İlçe</dt>
          <dd class="text-gray-800 dark:text-gray-100">
            {{ [user?.il, user?.ilce].filter(Boolean).join(' / ') || '—' }}
          </dd>
        </div>
        <div>
          <dt class="text-xs text-gray-500 dark:text-gray-400">Birim</dt>
          <dd class="text-gray-800 dark:text-gray-100">{{ departmentName }}</dd>
        </div>
      </dl>

      <div class="border-t border-gray-200 dark:border-gray-700">
        <NuxtLink
          to="/profile"
          class="block px-4 py-2.5 text-sm text-gray-700 hover:bg-gray-100 dark:text-gray-200 dark:hover:bg-gray-700"
          role="menuitem"
          @click="open = false"
        >
          Profilim
        </NuxtLink>
        <NuxtLink
          to="/settings"
          class="block px-4 py-2.5 text-sm text-gray-700 hover:bg-gray-100 dark:text-gray-200 dark:hover:bg-gray-700"
          role="menuitem"
          @click="open = false"
        >
          Ayarlar
        </NuxtLink>
        <button
          type="button"
          class="block w-full px-4 py-2.5 text-left text-sm text-red-500 hover:bg-gray-100 dark:hover:bg-gray-700"
          role="menuitem"
          @click="logout"
        >
          Çıkış Yap
        </button>
      </div>
    </div>

    <AvatarLightbox ref="lightbox" :src="avatarUrl" alt="Profil" />
  </div>
</template>

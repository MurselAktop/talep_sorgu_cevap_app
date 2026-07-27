<script setup lang="ts">
const { user, isAdmin, isMudur, canViewIncoming, signOut, fetchProfile } = useAuth()
const { openPanel: openDmPanel, unreadTotal: dmUnread, refreshUnread } = useDmPanel()
const { openChat: openAiChat } = useAiAssistant()
const { tick: pageRefreshTick, refreshing, refresh: refreshPage } = usePageRefresh()
const supabase = useSupabase()
const route = useRoute()
const mobileOpen = ref(false)
const search = ref('')
const incomingCount = ref(0)
let dmPoll: ReturnType<typeof setInterval> | null = null

const allItems = computed(() =>
  visibleNavItems({
    isAdmin: isAdmin.value,
    isMudur: isMudur.value,
    canViewIncoming: canViewIncoming.value,
  }),
)
const mainItems = computed(() => allItems.value.filter((i) => !i.footer))
const footerItems = computed(() => allItems.value.filter((i) => i.footer))

function isActive(to?: string) {
  if (!to) return false
  return route.path === to || route.path.startsWith(`${to}/`)
}

async function onNavClick(item: { action?: string }) {
  mobileOpen.value = false
  if (item.action === 'openDm') openDmPanel()
  if (item.action === 'openAi') openAiChat()
  if (item.action === 'logout') {
    const ok = window.confirm('Çıkış yapmak istiyor musunuz?')
    if (!ok) return
    await signOut()
    await navigateTo('/login')
  }
}

async function loadBadge() {
  if (!canViewIncoming.value || !user.value) return
  try {
    let q = supabase.from('requests').select('id', { count: 'exact', head: true }).eq('status', 'acik')
    if (user.value.role === 'personel') q = q.eq('assigned_to', user.value.id)
    else if (user.value.role === 'mudur') q = q.eq('department_id', user.value.department_id)
    const { count } = await q
    incomingCount.value = count || 0
  } catch {
    incomingCount.value = 0
  }
}

function onSearch() {
  const q = search.value.trim()
  if (!q) return
  navigateTo({ path: canViewIncoming.value ? '/requests/incoming' : '/requests/mine', query: { q } })
}

async function onRefresh() {
  await refreshPage(async () => {
    await Promise.all([
      loadBadge(),
      canViewIncoming.value ? refreshUnread() : Promise.resolve(),
      fetchProfile(),
    ])
  })
}

watch(() => route.path, () => { mobileOpen.value = false })
onMounted(() => {
  void loadBadge()
  if (canViewIncoming.value) {
    void refreshUnread()
    dmPoll = setInterval(() => { void refreshUnread() }, 15000)
  }
})
onUnmounted(() => {
  if (dmPoll) clearInterval(dmPoll)
})
</script>

<template>
  <div class="flex h-screen overflow-hidden bg-slate-50 dark:bg-gray-900">
    <!-- Sidebar -->
    <aside
      class="fixed inset-y-0 left-0 z-40 flex w-60 flex-col border-r border-gray-200 bg-slate-50 transition-transform duration-150 lg:static lg:translate-x-0 dark:border-gray-700 dark:bg-gray-800"
      :class="mobileOpen ? 'translate-x-0' : '-translate-x-full lg:translate-x-0'"
    >
      <div class="flex h-14 items-center gap-2.5 border-b border-gray-200 px-4 dark:border-gray-700">
        <div class="flex h-8 w-8 items-center justify-center rounded-lg bg-blue-600">
          <svg class="h-4 w-4 text-white" viewBox="0 0 24 24" fill="currentColor">
            <path d="M12 2 3 7v10l9 5 9-5V7l-9-5Zm0 2.2 6.5 3.6v7.4L12 18.8l-6.5-3.6V7.8L12 4.2Z" />
          </svg>
        </div>
        <span class="text-sm font-semibold tracking-wide text-gray-900 dark:text-white">TŞYS</span>
      </div>

      <nav class="flex flex-1 flex-col overflow-y-auto p-3">
        <div class="space-y-1">
          <template v-for="item in mainItems" :key="item.label + (item.to || item.action || '')">
            <button
              v-if="item.action"
              type="button"
              class="nav-item-idle w-full text-left"
              @click="onNavClick(item)"
            >
              <NavIcon :name="item.icon" class="h-4 w-4 shrink-0 text-gray-500 dark:text-gray-400" />
              <span class="flex-1 truncate">{{ item.label }}</span>
              <span
                v-if="item.badgeKey === 'dm' && dmUnread > 0"
                class="rounded-md bg-red-500 px-1.5 py-0.5 text-[10px] font-semibold leading-none text-white shadow-sm"
              >
                {{ dmUnread > 99 ? '99+' : dmUnread }}
              </span>
            </button>
            <NuxtLink
              v-else-if="item.to"
              :to="item.to"
              :class="isActive(item.to) ? 'nav-item-active' : 'nav-item-idle'"
              @click="mobileOpen = false"
            >
              <NavIcon
                :name="item.icon"
                class="h-4 w-4 shrink-0"
                :class="isActive(item.to) ? 'text-blue-600 dark:text-blue-300' : 'text-gray-500 dark:text-gray-400'"
              />
              <span class="flex-1 truncate">{{ item.label }}</span>
              <span
                v-if="item.badgeKey === 'incoming' && incomingCount > 0"
                class="rounded-md bg-blue-600 px-1.5 py-0.5 text-[10px] font-semibold leading-none text-white shadow-sm"
              >
                {{ incomingCount }}
              </span>
            </NuxtLink>
          </template>
        </div>

        <div class="mt-auto space-y-1 border-t border-gray-200 pt-3 dark:border-gray-700">
          <template v-for="item in footerItems" :key="'f-' + item.label">
            <button
              v-if="item.action === 'logout'"
              type="button"
              class="nav-item-idle w-full text-left text-red-600 hover:bg-red-500/10 dark:text-red-400"
              @click="onNavClick(item)"
            >
              <NavIcon :name="item.icon" class="h-4 w-4 shrink-0" />
              <span class="flex-1 truncate">{{ item.label }}</span>
            </button>
            <NuxtLink
              v-else-if="item.to"
              :to="item.to"
              :class="isActive(item.to) ? 'nav-item-active' : 'nav-item-idle'"
              @click="mobileOpen = false"
            >
              <NavIcon
                :name="item.icon"
                class="h-4 w-4 shrink-0"
                :class="isActive(item.to) ? 'text-blue-600 dark:text-blue-300' : 'text-gray-500 dark:text-gray-400'"
              />
              <span class="flex-1 truncate">{{ item.label }}</span>
            </NuxtLink>
          </template>
        </div>
      </nav>
    </aside>

    <div
      v-if="mobileOpen"
      class="fixed inset-0 z-30 bg-black/50 lg:hidden"
      @click="mobileOpen = false"
    />

    <div class="flex min-w-0 flex-1 flex-col">
      <header
        class="flex h-14 shrink-0 items-center gap-3 border-b border-gray-200 bg-slate-50 px-4 dark:border-gray-700 dark:bg-gray-800 lg:px-6"
      >
        <button
          type="button"
          class="rounded-lg border border-gray-300 p-2 text-gray-600 hover:bg-gray-100 lg:hidden dark:border-gray-700 dark:text-gray-300 dark:hover:bg-gray-700"
          @click="mobileOpen = !mobileOpen"
        >
          <svg class="h-4 w-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M4 6h16M4 12h16M4 18h16" />
          </svg>
        </button>

        <form class="relative min-w-0 flex-1 max-w-md" @submit.prevent="onSearch">
          <svg
            class="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
          >
            <circle cx="11" cy="11" r="7" />
            <path d="m20 20-3.5-3.5" />
          </svg>
          <input
            v-model="search"
            type="search"
            placeholder="Ara..."
            class="w-full rounded-lg border-gray-300 bg-gray-50 py-2 pl-9 pr-3 dark:border-gray-700 dark:bg-gray-900"
          />
        </form>

        <div class="ml-auto flex items-center gap-2.5">
          <button
            type="button"
            class="flex h-9 w-9 items-center justify-center rounded-lg border border-gray-300 text-gray-600 hover:bg-gray-100 disabled:opacity-50 dark:border-gray-700 dark:text-gray-300 dark:hover:bg-gray-700"
            title="Verileri yenile"
            :disabled="refreshing"
            @click="onRefresh"
          >
            <svg
              class="h-4 w-4"
              :class="refreshing ? 'animate-spin' : ''"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
            >
              <path d="M21 12a9 9 0 1 1-2.6-6.3" />
              <path d="M21 3v6h-6" />
            </svg>
          </button>
          <ThemeToggle />
          <NotificationBell :refresh-key="pageRefreshTick" />
          <ProfileDropdown />
        </div>
      </header>

      <main class="flex-1 overflow-y-auto bg-slate-50 p-4 dark:bg-gray-900 md:p-6 lg:p-8">
        <div :key="pageRefreshTick" class="mx-auto w-full max-w-7xl">
          <slot />
        </div>
      </main>
    </div>

    <MessagesAiFab />
    <DmSidebar />
  </div>
</template>

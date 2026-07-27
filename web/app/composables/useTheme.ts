const THEME_KEY = 'tsys_web_theme'

export type ThemeMode = 'light' | 'dark'

export function useTheme() {
  const mode = useState<ThemeMode>('theme-mode', () => 'dark')

  function apply(next: ThemeMode) {
    mode.value = next
    if (import.meta.client) {
      document.documentElement.classList.toggle('dark', next === 'dark')
      localStorage.setItem(THEME_KEY, next)
    }
  }

  function toggle() {
    apply(mode.value === 'dark' ? 'light' : 'dark')
  }

  function init() {
    if (!import.meta.client) return
    const saved = localStorage.getItem(THEME_KEY) as ThemeMode | null
    if (saved === 'dark' || saved === 'light') {
      apply(saved)
      return
    }
    apply('dark')
  }

  const isDark = computed(() => mode.value === 'dark')

  return { mode, isDark, apply, toggle, init }
}

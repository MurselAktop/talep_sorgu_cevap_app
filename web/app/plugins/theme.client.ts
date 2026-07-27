export default defineNuxtPlugin(() => {
  const { init } = useTheme()
  init()
  // İlk boyamada koyu sınıfı hemen uygula (FOUC azaltma)
  if (import.meta.client && !document.documentElement.classList.contains('dark')) {
    const saved = localStorage.getItem('tsys_web_theme')
    if (saved !== 'light') document.documentElement.classList.add('dark')
  }
})

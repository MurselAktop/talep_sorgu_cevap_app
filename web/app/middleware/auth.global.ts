export default defineNuxtRouteMiddleware((to) => {
  const { isLoggedIn, sessionReady } = useAuth()

  if (!sessionReady.value) return

  const publicPaths = [
    '/login',
    '/register',
    '/personnel-register',
    '/guest',
    '/guest/create',
    '/guest/query',
    '/forgot-password',
  ]

  const isPublic = publicPaths.some((p) => to.path === p || to.path.startsWith(`${p}/`))

  if (!isLoggedIn.value && !isPublic && to.path !== '/') {
    return navigateTo('/login')
  }

  if (isLoggedIn.value && (to.path === '/login' || to.path === '/register' || to.path === '/')) {
    return navigateTo('/home')
  }
})

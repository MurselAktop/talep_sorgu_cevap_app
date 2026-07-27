export type UserRole = 'vatandas' | 'personel' | 'mudur' | 'admin'

export interface UserProfile {
  id: string
  email: string | null
  full_name: string | null
  role: UserRole
  department_id: number | null
  phone: string | null
  il: string | null
  ilce: string | null
  is_active: boolean | null
  avatar_url?: string | null
}

export function useAuth() {
  const supabase = useSupabase()
  const user = useState<UserProfile | null>('auth-profile', () => null)
  const sessionReady = useState('auth-ready', () => false)
  const loading = useState('auth-loading', () => false)

  const isLoggedIn = computed(() => !!user.value)
  const role = computed(() => user.value?.role ?? null)
  const isAdmin = computed(() => role.value === 'admin')
  const isMudur = computed(() => role.value === 'mudur')
  const isPersonel = computed(() => role.value === 'personel')
  const isVatandas = computed(() => role.value === 'vatandas')
  const canViewIncoming = computed(
    () => role.value === 'admin' || role.value === 'mudur' || role.value === 'personel',
  )

  async function fetchProfile(): Promise<UserProfile | null> {
    const { data: sessionData } = await supabase.auth.getSession()
    const uid = sessionData.session?.user?.id
    if (!uid) {
      user.value = null
      return null
    }

    const { data, error } = await supabase
      .from('users')
      .select('id, email, full_name, role, department_id, phone, il, ilce, is_active, avatar_url')
      .eq('id', uid)
      .maybeSingle()

    if (error || !data) {
      user.value = null
      return null
    }

    if (data.is_active === false) {
      await supabase.auth.signOut()
      user.value = null
      throw new Error('Hesabınız pasifleştirilmiş.')
    }

    user.value = data as UserProfile
    return user.value
  }

  async function init() {
    if (sessionReady.value) return
    loading.value = true
    try {
      await fetchProfile()
    } catch {
      user.value = null
    } finally {
      sessionReady.value = true
      loading.value = false
    }

    supabase.auth.onAuthStateChange(async (event) => {
      if (event === 'SIGNED_OUT') {
        user.value = null
        return
      }
      if (event === 'SIGNED_IN' || event === 'TOKEN_REFRESHED' || event === 'USER_UPDATED') {
        try {
          await fetchProfile()
        } catch {
          user.value = null
        }
      }
    })
  }

  async function signIn(email: string, password: string) {
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    if (error) throw error
    return fetchProfile()
  }

  async function signUp(payload: {
    email: string
    password: string
    fullName: string
    tcNo: string
    phone: string
    il: string
    ilce: string
    inviteCode?: string
  }) {
    const { error } = await supabase.auth.signUp({
      email: payload.email,
      password: payload.password,
      options: {
        data: {
          full_name: payload.fullName,
          tc_no: payload.tcNo,
          phone: payload.phone,
          il: payload.il,
          ilce: payload.ilce,
          ...(payload.inviteCode ? { invite_code: payload.inviteCode } : {}),
        },
      },
    })
    if (error) throw error
    await supabase.auth.signOut()
  }

  async function checkRegistrationAvailability(tcNo: string, inviteCode?: string) {
    const { error } = await supabase.rpc('check_registration_availability', {
      p_tc_no: tcNo,
      p_invite_code: inviteCode ?? null,
    })
    if (error) throw error
  }

  async function signOut() {
    await supabase.auth.signOut()
    user.value = null
  }

  return {
    user,
    sessionReady,
    loading,
    isLoggedIn,
    role,
    isAdmin,
    isMudur,
    isPersonel,
    isVatandas,
    canViewIncoming,
    init,
    fetchProfile,
    signIn,
    signUp,
    checkRegistrationAvailability,
    signOut,
  }
}

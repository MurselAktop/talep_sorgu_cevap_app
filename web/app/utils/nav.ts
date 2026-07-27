export interface NavItem {
  to?: string
  label: string
  icon: 'home' | 'requests' | 'people' | 'reports' | 'settings' | 'create' | 'messages' | 'assistant' | 'profile' | 'logout'
  badgeKey?: 'incoming' | 'dm'
  staffOnly?: boolean
  adminOnly?: boolean
  managerOrAdmin?: boolean
  always?: boolean
  /** Alt bölüm (profil / ayarlar / çıkış) */
  footer?: boolean
  /** Sayfa yerine aksiyon */
  action?: 'openDm' | 'openAi' | 'logout'
}

export const navItems: NavItem[] = [
  { to: '/home', label: 'Dashboard', icon: 'home', always: true },
  { to: '/requests/create', label: 'Yeni Talep', icon: 'create', always: true },
  { label: 'Arıza Asistanı', icon: 'assistant', always: true, action: 'openAi' },
  { to: '/requests/mine', label: 'Taleplerim', icon: 'requests', always: true },
  { to: '/requests/incoming', label: 'Gelen Talepler', icon: 'requests', badgeKey: 'incoming', staffOnly: true },
  { label: 'Mesajlar', icon: 'messages', staffOnly: true, action: 'openDm', badgeKey: 'dm' },
  { to: '/admin/users', label: 'Vatandaş / Personel', icon: 'people', adminOnly: true },
  { to: '/stats', label: 'Detaylı Raporlar', icon: 'reports', managerOrAdmin: true },

  { to: '/profile', label: 'Profilim', icon: 'profile', always: true, footer: true },
  { to: '/settings', label: 'Ayarlar', icon: 'settings', always: true, footer: true },
  { label: 'Çıkış Yap', icon: 'logout', always: true, footer: true, action: 'logout' },
]

export function visibleNavItems(opts: {
  isAdmin: boolean
  isMudur: boolean
  canViewIncoming: boolean
}) {
  return navItems.filter((item) => {
    if (item.always) return true
    if (item.adminOnly) return opts.isAdmin
    if (item.managerOrAdmin) return opts.isAdmin || opts.isMudur
    if (item.staffOnly) return opts.canViewIncoming
    return true
  })
}

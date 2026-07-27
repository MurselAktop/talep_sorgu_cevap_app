export const statusLabels: Record<string, string> = {
  acik: 'Açık',
  cozuldu: 'Çözüldü (Onay Bekliyor)',
  onaylandi: 'Onaylandı',
  reddedildi: 'Reddedildi',
  iptal: 'İptal Edildi',
}

export const statusColors: Record<string, string> = {
  acik: 'bg-status-acik/20 text-status-acik',
  cozuldu: 'bg-status-cozuldu/20 text-status-cozuldu',
  onaylandi: 'bg-status-onaylandi/20 text-status-onaylandi',
  reddedildi: 'bg-status-reddedildi/20 text-status-reddedildi',
  iptal: 'bg-status-iptal/20 text-status-iptal',
}

export const roleLabels: Record<string, string> = {
  vatandas: 'Vatandaş',
  personel: 'Personel',
  mudur: 'Müdür',
  admin: 'Admin',
}

export function escapeFilterValue(raw: string): string {
  return raw.replaceAll('\\', '\\\\').replaceAll('"', '\\"')
}

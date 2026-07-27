export function useDmPanel() {
  const open = useState('dm-panel-open', () => false)
  const conversationId = useState<string | null>('dm-panel-conversation', () => null)
  const otherName = useState<string>('dm-panel-other-name', () => '')
  const unreadTotal = useState('dm-unread-total', () => 0)

  function openPanel(opts?: { conversationId?: string | null; otherName?: string }) {
    open.value = true
    if (opts?.conversationId !== undefined) conversationId.value = opts.conversationId
    if (opts?.otherName !== undefined) otherName.value = opts.otherName
  }

  function closePanel() {
    open.value = false
  }

  function openConversation(id: string, name = '') {
    conversationId.value = id
    otherName.value = name
    open.value = true
  }

  function backToList() {
    conversationId.value = null
    otherName.value = ''
  }

  async function refreshUnread() {
    try {
      const supabase = useSupabase()
      const { data } = await supabase.rpc('get_my_dm_conversations')
      const list = Array.isArray(data) ? data : []
      unreadTotal.value = list.reduce(
        (sum: number, c: any) => sum + Number(c.unread_count || 0),
        0,
      )
    } catch {
      /* sessiz */
    }
  }

  return {
    open,
    conversationId,
    otherName,
    unreadTotal,
    openPanel,
    closePanel,
    openConversation,
    backToList,
    refreshUnread,
  }
}

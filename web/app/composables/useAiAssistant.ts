export function useAiAssistant() {
  const open = useState('ai-assistant-open', () => false)

  function openChat() {
    open.value = true
  }

  function closeChat() {
    open.value = false
  }

  function toggleChat() {
    open.value = !open.value
  }

  return { open, openChat, closeChat, toggleChat }
}

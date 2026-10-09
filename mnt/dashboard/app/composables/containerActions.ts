export type ContainerAction = 'start' | 'stop' | 'restart'

export const ACTION_LABELS: Record<ContainerAction, { verb: string, done: string }> = {
  start: { verb: 'Démarrer', done: 'démarré' },
  stop: { verb: 'Arrêter', done: 'arrêté' },
  restart: { verb: 'Redémarrer', done: 'redémarré' },
}

/** Action sur un conteneur : demande de confirmation, puis exécution suivie conteneur par conteneur */
export function useContainerActions() {
  const toast = useToast()
  const pending = ref<{ name: string, action: ContainerAction } | null>(null)
  const running = ref<Record<string, ContainerAction>>({})
  const confirmOpen = computed({
    get: () => pending.value !== null,
    set: (open) => { if (!open) pending.value = null },
  })

  async function confirmAction() {
    if (!pending.value) return
    const { name, action } = pending.value
    pending.value = null
    running.value[name] = action
    const failure = await postAction(`/api/containers/${encodeURIComponent(name)}/${action}`)
    if (failure) {
      toast.add({ title: `Échec : ${ACTION_LABELS[action].verb.toLowerCase()} ${name}`, description: failure, color: 'error', icon: 'i-lucide-circle-x' })
    } else {
      toast.add({ title: `${name} ${ACTION_LABELS[action].done}`, color: 'success', icon: 'i-lucide-circle-check' })
    }
    delete running.value[name]
    await refreshNuxtData('containers')
  }

  return { pending, running, confirmOpen, confirmAction }
}

export type ContainerActions = ReturnType<typeof useContainerActions>

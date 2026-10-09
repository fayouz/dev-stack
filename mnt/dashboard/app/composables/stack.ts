// Une seule clé par source : toutes les pages et composants partagent les mêmes données
export const useContainers = () => useFetch('/api/containers', { key: 'containers' })
export const useHost = () => useFetch('/api/host', { key: 'host' })
export const useUpdates = () => useFetch('/api/updates', { key: 'updates' })
export const useBackups = () => useFetch('/api/backups', { key: 'backups' })
export const useVulnerabilities = () => useFetch('/api/vulnerabilities', { key: 'vulnerabilities' })

export const useHistory = (range: Ref<string>) =>
  useFetch('/api/history', { key: 'history', query: { range } })

export const FAST_REFRESH = ['containers', 'host']
export const FAST_REFRESH_MS = 10_000
export const ALL_REFRESH = [...FAST_REFRESH, 'updates', 'backups', 'vulnerabilities']

/** Rafraîchit `key` toutes les 5 s tant que `busy` est vrai (sauvegarde ou analyse en cours) */
export function usePollWhile(busy: Ref<boolean>, key: string) {
  let timer: ReturnType<typeof setInterval> | undefined
  watch(busy, (value) => {
    clearInterval(timer)
    if (value) timer = setInterval(() => refreshNuxtData(key), 5_000)
  }, { immediate: true })
  onBeforeUnmount(() => clearInterval(timer))
}

/** POST vers une action du dashboard ; renvoie le message d'erreur, ou null si tout s'est bien passé */
export async function postAction(url: string) {
  try {
    await $fetch(url, { method: 'POST', headers: { 'X-Requested-With': 'dashboard' } })
    return null
  } catch (err) {
    return (err as { data?: { statusMessage?: string } }).data?.statusMessage ?? String(err)
  }
}

export const useLastRefresh = () => useState('lastRefresh', () => new Date())

// Pause globale de l'actualisation automatique (timer du layout, courbes, logs)
export const useRefreshPaused = () => useState('refreshPaused', () => false)

/** Problèmes de toutes les catégories suivies : stack et outils arrêtés ou malades, applications malades */
export function useProblems() {
  const { data } = useContainers()
  return computed(() => (data.value?.containers ?? []).filter((c) => {
    if (c.category === 'stack' || c.category === 'tools') {
      return !(c.onDemand && c.state !== 'running') && (c.state !== 'running' || c.health === 'unhealthy')
    }
    // Une application arrêtée l'est souvent volontairement : seuls les états anormaux comptent
    return c.category === 'app' && (c.health === 'unhealthy' || c.state === 'restarting' || c.state === 'dead')
  }))
}

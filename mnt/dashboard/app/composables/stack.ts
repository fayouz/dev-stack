// Une seule clé par source : toutes les pages et composants partagent les mêmes données
export const useContainers = () => useFetch('/api/containers', { key: 'containers' })
export const useHost = () => useFetch('/api/host', { key: 'host' })
export const useUpdates = () => useFetch('/api/updates', { key: 'updates' })
export const useBackups = () => useFetch('/api/backups', { key: 'backups' })

export const useHistory = (range: Ref<string>) =>
  useFetch('/api/history', { key: 'history', query: { range } })

export const FAST_REFRESH = ['containers', 'host']
export const FAST_REFRESH_MS = 10_000
export const ALL_REFRESH = [...FAST_REFRESH, 'updates', 'backups']

export const useLastRefresh = () => useState('lastRefresh', () => new Date())

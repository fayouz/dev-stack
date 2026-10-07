export interface DockerContainer {
  Id: string
  Names: string[]
  Image: string
  State: string
  Status: string
  Created: number
  Labels: Record<string, string>
}

// Arrêter ces conteneurs couperait l'accès au dashboard lui-même
export const STOP_PROTECTED = ['traefik', 'dashboard', 'docker-socket-proxy', 'docker-socket-proxy-actions']

// Sur une machine chargée (des dizaines de conteneurs sous WSL), lister les conteneurs
// prend plusieurs secondes. Une seule requête à la fois, partagée par tous les appelants,
// et la dernière liste connue sert de secours si Docker ne répond pas à temps.
const CACHE_MS = 4000
let cache: { at: number, data: DockerContainer[] } | null = null
let inflight: Promise<DockerContainer[]> | null = null

export async function listContainers(): Promise<DockerContainer[]> {
  if (cache && Date.now() - cache.at < CACHE_MS) return cache.data
  inflight ??= $fetch<DockerContainer[]>('/containers/json', {
    baseURL: useRuntimeConfig().dockerHost,
    query: { all: 'true' },
    timeout: 15_000,
  })
    .then((data) => {
      cache = { at: Date.now(), data }
      return data
    })
    .finally(() => { inflight = null })
  try {
    return await inflight
  } catch (error) {
    if (cache) return cache.data
    throw error
  }
}

/** Date de la liste renvoyée en dernier (pour signaler des données anciennes). */
export const containersListedAt = () => cache?.at ?? null

export function containerName(container: DockerContainer) {
  return container.Names[0]?.replace(/^\//, '') ?? container.Id.slice(0, 12)
}

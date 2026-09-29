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

export function listContainers() {
  const { dockerHost } = useRuntimeConfig()
  return $fetch<DockerContainer[]>('/containers/json', {
    baseURL: dockerHost,
    query: { all: 'true' },
    timeout: 5000,
  })
}

export function containerName(container: DockerContainer) {
  return container.Names[0]?.replace(/^\//, '') ?? container.Id.slice(0, 12)
}

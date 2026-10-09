function publicUrl(labels: Record<string, string>) {
  if (labels['glance.url']) return labels['glance.url']
  for (const [key, value] of Object.entries(labels)) {
    const router = key.match(/^traefik\.http\.routers\.([^.]+)\.rule$/)?.[1]
    if (!router) continue
    const host = value.match(/Host\(`([^`]+)`\)/)?.[1]
    // HTTPS pour les routeurs en TLS (dev-stack), HTTP pour les autres projets
    if (host) return `${labels[`traefik.http.routers.${router}.tls`] === 'true' ? 'https' : 'http'}://${host}`
  }
  return null
}

// Services de la stack : catégorie lue dans le label `dashboard.category` (stack ou tools).
// Tout conteneur d'un autre projet Compose est une application en développement ;
// sans projet Compose (helpers d'IDE, conteneurs ponctuels), il est rangé dans « autres ».
const CATEGORY_ORDER = ['stack', 'tools', 'app', 'other']
function category(labels: Record<string, string>, stackProject: string) {
  const project = labels['com.docker.compose.project']
  if (!project) return 'other'
  if (project !== stackProject) return 'app'
  return labels['dashboard.category'] === 'tools' ? 'tools' : 'stack'
}

function health(status: string) {
  if (status.includes('(healthy)')) return 'healthy'
  if (status.includes('(unhealthy)')) return 'unhealthy'
  if (status.includes('(health: starting)')) return 'starting'
  return null
}

export default defineEventHandler(async () => {
  const [containers, cpu, memory] = await Promise.allSettled([
    listContainers(),
    promByLabel('sum by (name) (rate(container_cpu_usage_seconds_total{name!=""}[2m])) * 100', 'name'),
    promByLabel('sum by (name) (container_memory_working_set_bytes{name!=""})', 'name'),
  ])

  if (containers.status === 'rejected') {
    throw createError({ statusCode: 502, statusMessage: `API Docker injoignable : ${containers.reason}` })
  }
  const stackProject = useRuntimeConfig().public.defaultProject
  const cpuByName = cpu.status === 'fulfilled' ? cpu.value : {}
  const memoryByName = memory.status === 'fulfilled' ? memory.value : {}

  return {
    metricsAvailable: cpu.status === 'fulfilled',
    listedAt: containersListedAt(),
    containers: containers.value
      .map((container) => {
        const name = containerName(container)
        const running = container.State === 'running'
        return {
          name,
          project: container.Labels['com.docker.compose.project'] ?? null,
          category: category(container.Labels, stackProject) as 'stack' | 'tools' | 'app' | 'other',
          // Service lancé seulement quand on en a besoin : arrêté n'est pas un problème
          onDemand: container.Labels['dashboard.on-demand'] === 'true',
          image: container.Image,
          state: container.State,
          health: health(container.Status),
          status: container.Status,
          url: publicUrl(container.Labels),
          ports: publishedPorts(container),
          cpu: running ? cpuByName[name] ?? null : null,
          memory: running ? memoryByName[name] ?? null : null,
          stopProtected: STOP_PROTECTED.includes(name),
        }
      })
      .sort((a, b) => CATEGORY_ORDER.indexOf(a.category) - CATEGORY_ORDER.indexOf(b.category)
        || (a.project ?? '~').localeCompare(b.project ?? '~')
        || a.name.localeCompare(b.name)),
  }
})

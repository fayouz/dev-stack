function publicUrl(labels: Record<string, string>) {
  if (labels['glance.url']) return labels['glance.url']
  for (const [key, value] of Object.entries(labels)) {
    if (!/^traefik\.http\.routers\.[^.]+\.rule$/.test(key)) continue
    const host = value.match(/Host\(`([^`]+)`\)/)?.[1]
    if (host) return `http://${host}`
  }
  return null
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
  const cpuByName = cpu.status === 'fulfilled' ? cpu.value : {}
  const memoryByName = memory.status === 'fulfilled' ? memory.value : {}

  return {
    metricsAvailable: cpu.status === 'fulfilled',
    containers: containers.value
      .map((container) => {
        const name = containerName(container)
        const running = container.State === 'running'
        return {
          name,
          project: container.Labels['com.docker.compose.project'] ?? null,
          image: container.Image,
          state: container.State,
          health: health(container.Status),
          status: container.Status,
          url: publicUrl(container.Labels),
          cpu: running ? cpuByName[name] ?? null : null,
          memory: running ? memoryByName[name] ?? null : null,
          stopProtected: STOP_PROTECTED.includes(name),
        }
      })
      .sort((a, b) => (a.project ?? '~').localeCompare(b.project ?? '~') || a.name.localeCompare(b.name)),
  }
})

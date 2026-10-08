// Historique CPU / RAM d'un seul conteneur, pour le tiroir de détail de la page Services
const RANGES: Record<string, number> = { '15m': 900, '1h': 3600, '6h': 21_600, '24h': 86_400 }

export default defineEventHandler(async (event) => {
  const key = String(getQuery(event).range ?? '1h')
  const range = RANGES[key]
  if (!range) throw createError({ statusCode: 400, statusMessage: `Fenêtre inconnue : ${key}` })

  // Le nom n'entre dans la requête PromQL que s'il désigne un conteneur existant
  const name = getRouterParam(event, 'name') ?? ''
  if (!(await listContainers()).some(c => containerName(c) === name)) {
    throw createError({ statusCode: 404, statusMessage: `Conteneur introuvable : ${name}` })
  }

  const step = Math.max(15, Math.round(range / 120))
  const [cpu, memory] = await Promise.all([
    promRange(`sum(rate(container_cpu_usage_seconds_total{name="${name}"}[2m])) * 100`, range, step),
    promRange(`sum(container_memory_working_set_bytes{name="${name}"})`, range, step),
  ]).catch((error: Error) => {
    throw createError({ statusCode: 502, statusMessage: `Prometheus injoignable : ${error.message}` })
  })

  return {
    range: key,
    cpu: cpu[0]?.points ?? [],
    memory: memory[0]?.points ?? [],
  }
})

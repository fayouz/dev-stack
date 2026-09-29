// Fenêtres proposées par le dashboard, en secondes ; « live » = temps réel sur 5 min
const RANGES: Record<string, number> = { 'live': 300, '15m': 900, '1h': 3600, '6h': 21_600, '24h': 86_400 }
const TOP_CONTAINERS = 4

const CONTAINER_CPU = 'sum by (name) (rate(container_cpu_usage_seconds_total{name!=""}[2m])) * 100'

export default defineEventHandler(async (event) => {
  const key = String(getQuery(event).range ?? '15m')
  const range = RANGES[key]
  if (!range) throw createError({ statusCode: 400, statusMessage: `Fenêtre inconnue : ${key}` })
  // Temps réel : un point toutes les 5 s (collecte node-exporter à 5 s).
  // Sinon ~120 points par courbe, jamais plus fin que la collecte (15 s).
  const live = key === 'live'
  const step = live ? 5 : Math.max(15, Math.round(range / 120))
  const hostRate = live ? '30s' : '1m'

  // Les conteneurs les plus gourmands en moyenne sur la fenêtre
  const top = await promByLabel(`topk(${TOP_CONTAINERS}, avg_over_time((${CONTAINER_CPU})[${range}s:${step}s]))`, 'name')
    .catch(() => ({}))
  // Tri par nom : la couleur suit le conteneur, pas son rang
  const names = Object.keys(top).sort()

  const [cpu, memory, containers] = await Promise.all([
    promRange(`100 * (1 - avg(rate(node_cpu_seconds_total{mode="idle"}[${hostRate}])))`, range, step),
    promRange('100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)', range, step),
    names.length
      ? promRange(`sum by (name) (rate(container_cpu_usage_seconds_total{name=~"${names.join('|')}"}[2m])) * 100`, range, step)
      : Promise.resolve([]),
  ]).catch((error: Error) => {
    throw createError({ statusCode: 502, statusMessage: `Prometheus injoignable : ${error.message}` })
  })

  return {
    range: key,
    step,
    cpu: cpu[0]?.points ?? [],
    memory: memory[0]?.points ?? [],
    containers: names.map(name => ({
      name,
      points: containers.find(c => c.metric.name === name)?.points ?? [],
    })),
  }
})

interface VectorSample {
  metric: Record<string, string>
  value: [number, string]
}

async function query(expr: string) {
  const { prometheusUrl } = useRuntimeConfig()
  const res = await $fetch<{ data: { result: VectorSample[] } }>('/api/v1/query', {
    baseURL: prometheusUrl,
    query: { query: expr },
    timeout: 5000,
  })
  return res.data.result
}

/** Résultat d'une requête indexé par la valeur d'un label (ex. nom du conteneur) */
export async function promByLabel(expr: string, label: string) {
  const values: Record<string, number> = {}
  for (const sample of await query(expr)) {
    const key = sample.metric[label]
    if (key) values[key] = Number(sample.value[1])
  }
  return values
}

interface MatrixSample {
  metric: Record<string, string>
  values: [number, string][]
}

/** Série temporelle sur les `range` dernières secondes, en points [timestamp ms, valeur] */
export async function promRange(expr: string, range: number, step: number) {
  const { prometheusUrl } = useRuntimeConfig()
  const end = Math.floor(Date.now() / 1000)
  const res = await $fetch<{ data: { result: MatrixSample[] } }>('/api/v1/query_range', {
    baseURL: prometheusUrl,
    query: { query: expr, start: end - range, end, step },
    timeout: 5000,
  })
  return res.data.result.map(sample => ({
    metric: sample.metric,
    points: sample.values.map(([t, v]) => [t * 1000, Number(v)] as [number, number]),
  }))
}

/** Première valeur d'une requête, ou null si Prometheus ne répond pas */
export async function promScalar(expr: string) {
  try {
    const [sample] = await query(expr)
    return sample ? Number(sample.value[1]) : null
  } catch {
    return null
  }
}

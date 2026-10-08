<script setup lang="ts">
// Tiroir de détail d'un service : historique CPU / RAM et logs en temps réel
const props = defineProps<{ name: string }>()
const tab = defineModel<'activity' | 'logs'>('tab', { default: 'activity' })
const open = defineModel<boolean>('open', { default: false })

const TABS = [
  { label: 'Activité', value: 'activity', icon: 'i-lucide-chart-line' },
  { label: 'Logs', value: 'logs', icon: 'i-lucide-scroll-text' },
]
const RANGES = [
  { label: '15 min', value: '15m' },
  { label: '1 h', value: '1h' },
  { label: '6 h', value: '6h' },
  { label: '24 h', value: '24h' },
]
const range = ref('1h')

const { data, error, status, refresh } = useFetch(() => `/api/history/${encodeURIComponent(props.name)}`, {
  query: { range },
  immediate: false,
})
watch([open, tab, () => props.name], () => {
  if (open.value && tab.value === 'activity') refresh()
}, { immediate: true })

// Rafraîchi toutes les 30 s tant que l'onglet est affiché
let timer: ReturnType<typeof setInterval> | undefined
onMounted(() => {
  timer = setInterval(() => {
    if (open.value && tab.value === 'activity') refresh()
  }, 30_000)
})
onBeforeUnmount(() => clearInterval(timer))

const points = computed(() => (data.value?.cpu ?? []).map(([time, cpu], i) => ({
  time,
  cpu,
  memory: data.value?.memory[i]?.[1] ?? 0,
})))
const tick = (i: number) => {
  const p = points.value[i]
  if (!p) return ''
  const date = new Date(p.time)
  return range.value === '24h'
    ? date.toLocaleString('fr-FR', { weekday: 'short', hour: '2-digit', minute: '2-digit' })
    : date.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })
}
</script>

<template>
  <USlideover
    v-model:open="open"
    :title="name"
    description="Activité et logs du service"
    :ui="{ content: 'sm:max-w-3xl', body: 'flex flex-col gap-4' }"
  >
    <template #body>
      <div class="flex flex-wrap items-center justify-between gap-2">
        <UTabs v-model="tab" :items="TABS" :content="false" size="sm" />
        <UTabs v-if="tab === 'activity'" v-model="range" :items="RANGES" :content="false" size="xs" color="neutral" />
      </div>

      <template v-if="tab === 'activity'">
        <UAlert
          v-if="error"
          icon="i-lucide-triangle-alert"
          color="error"
          variant="subtle"
          title="Historique indisponible"
          :description="error.statusMessage"
        />
        <p v-else-if="data && !points.length" class="text-sm text-muted">
          Aucune mesure sur cette période : le service ne tournait pas.
        </p>
        <template v-else>
          <UCard>
            <template #header>
              <div class="flex items-baseline justify-between">
                <h3 class="font-semibold">CPU</h3>
                <span class="text-sm text-muted">{{ formatPercent(points.at(-1)?.cpu) }}</span>
              </div>
            </template>
            <AreaChart
              :data="points"
              :categories="{ cpu: { name: 'CPU', color: 'var(--viz-1)' } }"
              :height="180"
              :y-domain="[0, undefined]"
              :x-formatter="tick"
              :y-formatter="(v: number) => `${v} %`"
              :x-num-ticks="4"
              :y-num-ticks="4"
              :duration="0"
              hide-legend
              :class="{ 'opacity-60': status === 'pending' }"
            />
          </UCard>
          <UCard>
            <template #header>
              <div class="flex items-baseline justify-between">
                <h3 class="font-semibold">Mémoire</h3>
                <span class="text-sm text-muted">{{ formatBytes(points.at(-1)?.memory) }}</span>
              </div>
            </template>
            <AreaChart
              :data="points"
              :categories="{ memory: { name: 'Mémoire', color: 'var(--viz-2)' } }"
              :height="180"
              :y-domain="[0, undefined]"
              :x-formatter="tick"
              :y-formatter="(v: number) => formatBytes(v)"
              :x-num-ticks="4"
              :y-num-ticks="4"
              :duration="0"
              hide-legend
              :class="{ 'opacity-60': status === 'pending' }"
            />
          </UCard>
        </template>
      </template>

      <!-- Clé sur le nom : un autre service ouvre un nouveau flux -->
      <LogsCard v-else :key="name" :service="name" />
    </template>
  </USlideover>
</template>

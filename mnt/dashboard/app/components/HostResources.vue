<script setup lang="ts">
// Ressources de l'hôte : une ligne par ressource (barre linéaire + valeur + détail),
// avec la tendance des 15 dernières minutes pour le CPU et la mémoire.
const { data: host } = await useHost()
// Fenêtre fixe de 15 min, indépendante du sélecteur de période des courbes
const { data: trend } = await useFetch('/api/history', { key: 'history-15m', query: { range: '15m' } })

const paused = useRefreshPaused()
let timer: ReturnType<typeof setInterval> | undefined
onMounted(() => {
  timer = setInterval(() => {
    if (!paused.value) refreshNuxtData('history-15m')
  }, 30_000)
})
onBeforeUnmount(() => clearInterval(timer))

// Seuils : neutre sous 80 % (62 % de RAM est normal), élevé dès 80 %, critique dès 90 %
function level(value: number | null) {
  if (value != null && value >= 90) return { color: 'var(--viz-critical)', badge: 'error' as const, icon: 'i-lucide-octagon-alert', text: 'Critique' }
  if (value != null && value >= 80) return { color: 'var(--viz-warning)', badge: 'warning' as const, icon: 'i-lucide-triangle-alert', text: 'Élevé' }
  return { color: 'var(--viz-1)', badge: null, icon: null, text: null }
}

const percent = (part?: number, total?: number) => part != null && total ? 100 * part / total : null

const rows = computed(() => {
  const h = host.value
  return [
    {
      key: 'cpu',
      label: 'CPU',
      icon: 'i-lucide-cpu',
      value: h?.cpu ?? null,
      detail: `${h?.cores ?? '—'} cœurs · charge ${h?.load1?.toLocaleString('fr-FR', { maximumFractionDigits: 2 }) ?? '—'}`,
      trend: (trend.value?.cpu ?? []).map(p => p[1]),
    },
    {
      key: 'memory',
      label: 'Mémoire',
      icon: 'i-lucide-memory-stick',
      value: percent(h?.memory?.used, h?.memory?.total),
      detail: `${formatBytes(h?.memory?.used)} / ${formatBytes(h?.memory?.total)}`,
      trend: (trend.value?.memory ?? []).map(p => p[1]),
    },
    {
      key: 'disk',
      label: 'Disque',
      icon: 'i-lucide-hard-drive',
      value: percent(h?.disk?.used, h?.disk?.total),
      detail: `${formatBytes(h?.disk?.used)} / ${formatBytes(h?.disk?.total)}`,
      trend: [],
    },
  ].map(row => ({ ...row, level: level(row.value) }))
})
</script>

<template>
  <UCard :ui="{ header: 'px-4 py-3 sm:px-4', body: 'px-4 py-3 sm:px-4 sm:py-3' }">
    <template #header>
      <div class="flex items-center justify-between gap-2">
        <h3 class="font-semibold">Ressources de l'hôte</h3>
        <span v-if="host?.uptime != null" class="flex items-center gap-1 text-xs text-muted">
          <UIcon name="i-lucide-power" aria-hidden="true" /> allumé depuis {{ formatDuration(host.uptime) }}
        </span>
      </div>
    </template>

    <p v-if="host && !host.available" class="flex items-center gap-2 text-sm text-muted">
      <UIcon name="i-lucide-unplug" /> Prometheus injoignable : métriques indisponibles
    </p>

    <ul v-else class="flex flex-col divide-y divide-default">
      <li v-for="row in rows" :key="row.key" class="flex flex-col gap-1.5 py-3 first:pt-0 last:pb-0">
        <div class="flex items-center justify-between gap-2">
          <span class="flex items-center gap-1.5 text-sm text-default">
            <UIcon :name="row.icon" class="text-muted" aria-hidden="true" /> {{ row.label }}
          </span>
          <span class="flex items-center gap-2">
            <UBadge v-if="row.level.badge" :color="row.level.badge" variant="subtle" size="sm" :icon="row.level.icon!" :label="row.level.text!" />
            <span class="text-sm font-semibold text-highlighted tabular-nums">{{ formatPercent(row.value) }}</span>
          </span>
        </div>

        <!-- Barre linéaire ; repère discret à 80 % (seuil « élevé ») -->
        <div
          class="relative h-2 overflow-hidden rounded-full bg-accented"
          role="meter"
          :aria-label="row.label"
          aria-valuemin="0"
          aria-valuemax="100"
          :aria-valuenow="row.value != null ? Math.round(row.value) : undefined"
          :aria-valuetext="`${formatPercent(row.value)}${row.level.text ? ` (${row.level.text})` : ''}`"
        >
          <div
            class="h-full rounded-full transition-[width] duration-500 ease-out"
            :style="{ width: `${Math.min(100, Math.max(0, row.value ?? 0))}%`, background: row.level.color }"
          />
          <span class="absolute inset-y-0 left-[80%] w-0.5 bg-default" aria-hidden="true" />
        </div>

        <div class="flex min-h-5 items-center justify-between gap-2 text-xs text-muted">
          <span class="truncate">{{ row.detail }}</span>
          <Sparkline v-if="row.trend.length > 1" :values="row.trend" :label="row.label" />
        </div>
      </li>
    </ul>
  </UCard>
</template>

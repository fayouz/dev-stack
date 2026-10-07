<script setup lang="ts">
useHead({ title: 'Vue d\'ensemble' })

const RANGES = [
  { label: 'Temps réel', value: 'live', icon: 'i-lucide-radio' },
  { label: '15 min', value: '15m' },
  { label: '1 h', value: '1h' },
  { label: '6 h', value: '6h' },
  { label: '24 h', value: '24h' },
]
const range = ref('live')
const paused = ref(false)
const isLive = computed(() => range.value === 'live')

const { data: containers } = await useContainers()
const { data: host } = await useHost()
const { data: updates } = await useUpdates()
const { data: backups } = await useBackups()
const { data: history, status: historyStatus } = await useHistory(range)

// Temps réel : courbes rafraîchies toutes les 5 s (sauf pause) ; autres fenêtres toutes les 30 s
let tick = 0
let timer: ReturnType<typeof setInterval> | undefined
onMounted(() => {
  timer = setInterval(() => {
    tick++
    if (isLive.value ? !paused.value : tick % 6 === 0) refreshNuxtData('history')
  }, 5_000)
})
onBeforeUnmount(() => clearInterval(timer))

// --- Indicateurs par catégorie
const all = computed(() => containers.value?.containers ?? [])
const inCategory = (category: Category) => all.value.filter(c => c.category === category)
const tiles = computed(() => MAIN_CATEGORIES.map((key) => {
  const list = inCategory(key)
  const projects = new Set(list.map(c => c.project ?? 'sans projet')).size
  return {
    key,
    ...CATEGORIES[key],
    running: list.filter(c => c.state === 'running').length,
    total: list.length,
    hint: key === 'app' ? `${projects} projet${projects > 1 ? 's' : ''}` : CATEGORIES[key].description,
  }
}))
// Stack et outils : doivent toujours tourner. Les applications s'arrêtent souvent volontairement.
const platform = computed(() => all.value.filter(c => c.category === 'stack' || c.category === 'tools'))
const problems = computed(() => platform.value.filter(c => !(c.onDemand && c.state !== 'running') && (c.state !== 'running' || c.health === 'unhealthy')))

const lastBackup = computed(() => backups.value?.available ? backups.value.lastRun : null)

const serviceSegments = computed(() => {
  const count = (test: (c: typeof platform.value[number]) => boolean) => platform.value.filter(test).length
  return [
    { key: 'ok', label: 'Actifs', color: 'var(--viz-good)', icon: 'i-lucide-circle-check', count: count(c => c.state === 'running' && !c.health?.match(/unhealthy|starting/)) },
    { key: 'starting', label: 'Démarrage', color: 'var(--viz-warning)', icon: 'i-lucide-loader', count: count(c => c.state === 'restarting' || c.health === 'starting') },
    { key: 'unhealthy', label: 'Malades', color: 'var(--viz-critical)', icon: 'i-lucide-circle-x', count: count(c => c.state === 'running' && c.health === 'unhealthy') },
    { key: 'stopped', label: 'Arrêtés', color: 'var(--viz-stopped)', icon: 'i-lucide-circle-stop', count: count(c => !['running', 'restarting'].includes(c.state)) },
  ]
})

// --- Courbes
const timeLabel = (t: number) => new Date(t).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })

const hostData = computed(() => (history.value?.cpu ?? []).map(([time, cpu], i) => ({
  time,
  cpu,
  memory: history.value?.memory[i]?.[1] ?? 0,
})))
const hostTick = (i: number) => { const p = hostData.value[i]; return p ? timeLabel(p.time) : '' }

// Couleur fixée par conteneur (ordre alphabétique renvoyé par l'API), jamais par rang
const SERIES_COLORS = ['var(--viz-1)', 'var(--viz-2)', 'var(--viz-3)', 'var(--viz-4)']
const containerSeries = computed(() => (history.value?.containers ?? []).map((c, i) => ({
  ...c,
  color: SERIES_COLORS[i % SERIES_COLORS.length]!,
  current: c.points.at(-1)?.[1] ?? null,
})))
const containerCategories = computed(() => Object.fromEntries(containerSeries.value.map(c => [c.name, { name: c.name, color: c.color }])))
const containerData = computed(() => {
  const base = containerSeries.value.find(c => c.points.length)?.points ?? []
  return base.map(([time], i) => ({
    time,
    ...Object.fromEntries(containerSeries.value.map(c => [c.name, c.points[i]?.[1] ?? 0])),
  }))
})
const containerTick = (i: number) => { const p = containerData.value[i]; return p ? timeLabel(p.time) : '' }

// --- Classement mémoire
const topMemory = computed(() => (containers.value?.containers ?? [])
  .filter(c => c.memory != null)
  .sort((a, b) => b.memory! - a.memory!)
  .slice(0, 8)
  .map(c => ({ label: c.name, value: c.memory!, display: formatBytes(c.memory) })))
</script>

<template>
  <UDashboardPanel id="overview">
    <template #header>
      <PageNavbar title="Vue d'ensemble" />

      <UDashboardToolbar>
        <template #left>
          <UTabs v-model="range" :items="RANGES" :content="false" size="xs" color="neutral" />
        </template>
        <template #right>
          <UButton
            v-if="isLive"
            :icon="paused ? 'i-lucide-play' : 'i-lucide-pause'"
            :label="paused ? 'En pause' : 'En direct'"
            :color="paused ? 'neutral' : 'success'"
            variant="soft"
            size="xs"
            @click="paused = !paused"
          >
            <template v-if="!paused" #leading>
              <span class="relative flex size-2">
                <span class="absolute inline-flex size-full animate-ping rounded-full bg-success opacity-75" />
                <span class="relative inline-flex size-2 rounded-full bg-success" />
              </span>
            </template>
          </UButton>
        </template>
      </UDashboardToolbar>
    </template>

    <template #body>
      <!-- Indicateurs -->
      <div class="grid grid-cols-2 gap-4 md:grid-cols-3 2xl:grid-cols-6">
        <StatTile
          v-for="tile in tiles"
          :key="tile.key"
          :label="tile.label"
          :value="`${tile.running} / ${tile.total}`"
          :icon="tile.icon"
          :hint="tile.hint"
          :to="{ path: '/services', query: { category: tile.key } }"
        />
        <StatTile
          label="Problèmes"
          :value="problems.length"
          :icon="problems.length ? 'i-lucide-triangle-alert' : 'i-lucide-circle-check'"
          :status="problems.length ? 'error' : 'success'"
          :hint="problems.length ? `Stack et outils : ${problems.map(p => p.name).join(', ')}` : 'Stack et outils OK'"
          to="/services"
        />
        <StatTile
          label="Mises à jour"
          :value="updates?.updates.length ?? '—'"
          icon="i-lucide-package"
          :status="updates?.updates.length ? 'warning' : 'success'"
          :hint="updates ? `${updates.watched} conteneurs surveillés` : 'WUD injoignable'"
          to="/mises-a-jour"
        />
        <StatTile
          label="Dernière sauvegarde"
          :value="lastBackup && lastBackup.result !== 'none' ? formatRelative(lastBackup.at) : '—'"
          :icon="lastBackup?.result === 'error' ? 'i-lucide-circle-x' : 'i-lucide-archive'"
          :status="lastBackup?.result === 'error' ? 'error' : lastBackup?.result === 'ok' ? 'success' : 'neutral'"
          :hint="lastBackup?.result === 'error' ? 'Échec' : lastBackup?.result === 'ok' ? 'Réussie' : 'Aucune sauvegarde'"
          to="/sauvegardes"
        />
      </div>

      <!-- Jauges -->
      <div class="grid grid-cols-2 gap-4 xl:grid-cols-4">
        <GaugeChart
          label="CPU"
          icon="i-lucide-cpu"
          :value="host?.cpu"
          :detail="`${host?.cores ?? '—'} cœurs · charge ${host?.load1?.toFixed(2) ?? '—'}`"
        />
        <GaugeChart
          label="Mémoire"
          icon="i-lucide-memory-stick"
          :value="host?.memory ? 100 * host.memory.used / host.memory.total : null"
          :detail="`${formatBytes(host?.memory?.used)} / ${formatBytes(host?.memory?.total)}`"
        />
        <GaugeChart
          label="Disque"
          icon="i-lucide-hard-drive"
          :value="host?.disk ? 100 * host.disk.used / host.disk.total : null"
          :detail="`${formatBytes(host?.disk?.used)} / ${formatBytes(host?.disk?.total)} · uptime ${formatDuration(host?.uptime)}`"
        />
        <StatusDonut title="Stack et outils" :segments="serviceSegments" />
      </div>

      <!-- Applications en développement -->
      <ApplicationsCard />

      <!-- Courbes temps réel de l'hôte -->
      <div class="grid gap-4 xl:grid-cols-2">
        <UCard>
          <template #header>
            <div class="flex items-baseline justify-between">
              <h3 class="font-semibold">CPU de l'hôte</h3>
              <span class="text-sm text-muted">{{ formatPercent(hostData.at(-1)?.cpu) }}</span>
            </div>
          </template>
          <AreaChart
            :data="hostData"
            :categories="{ cpu: { name: 'CPU', color: 'var(--viz-1)' } }"
            :height="200"
            :y-domain="[0, 100]"
            :x-formatter="hostTick"
            :y-formatter="(v: number) => `${v} %`"
            :x-num-ticks="5"
            :y-num-ticks="4"
            :duration="0"
            hide-legend
            :class="{ 'opacity-60': historyStatus === 'pending' }"
          />
        </UCard>
        <UCard>
          <template #header>
            <div class="flex items-baseline justify-between">
              <h3 class="font-semibold">Mémoire de l'hôte</h3>
              <span class="text-sm text-muted">{{ formatPercent(hostData.at(-1)?.memory) }}</span>
            </div>
          </template>
          <AreaChart
            :data="hostData"
            :categories="{ memory: { name: 'Mémoire', color: 'var(--viz-1)' } }"
            :height="200"
            :y-domain="[0, 100]"
            :x-formatter="hostTick"
            :y-formatter="(v: number) => `${v} %`"
            :x-num-ticks="5"
            :y-num-ticks="4"
            :duration="0"
            hide-legend
          />
        </UCard>
      </div>

      <!-- Conteneurs -->
      <div class="grid gap-4 xl:grid-cols-3">
        <UCard class="xl:col-span-2">
          <template #header>
            <div class="flex flex-wrap items-center justify-between gap-2">
              <h3 class="font-semibold">CPU des conteneurs les plus actifs</h3>
              <!-- Légende avec valeur courante : identifie chaque série sans passer par la couleur seule -->
              <ul class="flex flex-wrap gap-x-4 gap-y-1 text-xs">
                <li v-for="s in containerSeries" :key="s.name" class="flex items-center gap-1.5">
                  <span class="h-0.5 w-3 rounded" :style="{ background: s.color }" />
                  <span class="text-default">{{ s.name }}</span>
                  <span class="font-semibold text-highlighted tabular-nums">{{ formatPercent(s.current) }}</span>
                </li>
              </ul>
            </div>
          </template>
          <LineChart
            v-if="containerData.length"
            :data="containerData"
            :categories="containerCategories"
            :height="220"
            :y-domain="[0, undefined]"
            :x-formatter="containerTick"
            :y-formatter="(v: number) => `${v} %`"
            :x-num-ticks="5"
            :y-num-ticks="4"
            :duration="0"
            hide-legend
          />
          <p v-else class="text-sm text-muted">Pas encore de données.</p>
        </UCard>

        <UCard>
          <template #header>
            <h3 class="font-semibold">Mémoire par conteneur</h3>
          </template>
          <BarList :items="topMemory" />
        </UCard>
      </div>

      <!-- Logs en temps réel -->
      <LogsCard />
    </template>
  </UDashboardPanel>
</template>

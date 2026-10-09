<script setup lang="ts">
import type { RouteLocationRaw } from 'vue-router'

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
const globalPaused = useRefreshPaused()
const isLive = computed(() => range.value === 'live')

const { data: containers } = await useContainers()
const { data: updates } = await useUpdates()
const { data: history, status: historyStatus } = await useHistory(range)

// Temps réel : courbes rafraîchies toutes les 5 s (sauf pause) ; autres fenêtres toutes les 30 s
let tick = 0
let timer: ReturnType<typeof setInterval> | undefined
onMounted(() => {
  timer = setInterval(() => {
    tick++
    if (globalPaused.value) return
    if (isLive.value ? !paused.value : tick % 6 === 0) refreshNuxtData('history')
  }, 5_000)
})
onBeforeUnmount(() => clearInterval(timer))

// --- Filtre de la liste des conteneurs, piloté par les indicateurs (nouveau clic : retiré)
const filter = ref<ContainerFilter | null>(null)
const toggleFilter = (key: ContainerFilter) => { filter.value = filter.value === key ? null : key }

// --- Indicateurs
const all = computed(() => containers.value?.containers ?? [])
// Problèmes de toutes les catégories (applications malades comprises), comme la cloche de la barre du haut
const problems = useProblems()
const plural = (n: number, word: string) => `${n} ${word}${n > 1 ? 's' : ''}`

interface Tile {
  key: ContainerFilter
  label: string
  value: string | number
  total?: number
  icon: string
  hint: string
  status: 'success' | 'warning' | 'error' | 'neutral'
  link: { to: RouteLocationRaw, label: string }
}

const tiles = computed<Tile[]>(() => {
  const category = (key: Exclude<Category, 'other'>): Tile => {
    const list = all.value.filter(c => c.category === key)
    const running = list.filter(c => c.state === 'running').length
    const failing = problems.value.filter(c => c.category === key).length
    const onDemand = list.filter(c => c.onDemand && c.state !== 'running').length
    let hint: string
    let status: Tile['status']
    if (key === 'app') {
      // Une application arrêtée l'est souvent volontairement : pas de statut, sauf en cas de panne
      const projects = new Set(list.map(c => c.project ?? 'sans projet')).size
      hint = failing ? `${plural(failing, 'conteneur')} en erreur` : plural(projects, 'projet')
      status = failing ? 'error' : 'neutral'
    } else {
      hint = failing
        ? `${plural(failing, 'conteneur')} en erreur`
        : onDemand ? `Tous actifs · ${onDemand} à la demande` : 'Tous actifs'
      status = failing ? 'error' : list.length ? 'success' : 'neutral'
    }
    return {
      key,
      label: CATEGORIES[key].label,
      value: running,
      total: list.length,
      icon: CATEGORIES[key].icon,
      hint,
      status,
      link: { to: { path: '/services', query: { category: key } }, label: `Ouvrir ${CATEGORIES[key].label} dans la page Services` },
    }
  }
  const pending = updates.value?.updates.length
  return [
    ...(['stack', 'tools', 'app'] as const).map(category),
    {
      key: 'problems',
      label: 'Problèmes',
      value: problems.value.length,
      icon: problems.value.length ? 'i-lucide-triangle-alert' : 'i-lucide-circle-check',
      hint: problems.value.length ? problems.value.map(p => p.name).join(', ') : 'Tout fonctionne',
      status: problems.value.length ? 'error' : 'success',
      link: { to: '/services', label: 'Ouvrir la page Services' },
    },
    {
      key: 'updates',
      label: 'Mises à jour',
      value: pending ?? '—',
      icon: 'i-lucide-package',
      hint: updates.value ? `${updates.value.watched} conteneurs surveillés` : 'WUD injoignable',
      status: pending ? 'warning' : updates.value ? 'success' : 'neutral',
      link: { to: '/mises-a-jour', label: 'Ouvrir la page Mises à jour' },
    },
  ]
})

// --- Courbes : un seul axe de temps pour les trois graphiques empilés
const hoverTime = ref<number | null>(null)

const domain = computed<[number, number]>(() => {
  const h = history.value
  const series = [h?.cpu ?? [], h?.memory ?? [], ...(h?.containers ?? []).map(c => c.points)].filter(s => s.length)
  if (!series.length) return [0, 1]
  return [Math.min(...series.map(s => s[0]![0])), Math.max(...series.map(s => s.at(-1)![0]))]
})
const hasData = computed(() => !!history.value?.cpu.length)

const hostCpu = computed<TimeSeries[]>(() => [{ key: 'cpu', name: 'CPU', color: 'var(--viz-1)', points: history.value?.cpu ?? [] }])
const hostMemory = computed<TimeSeries[]>(() => [{ key: 'memory', name: 'Mémoire', color: 'var(--viz-1)', points: history.value?.memory ?? [] }])

// Couleur fixée par conteneur (ordre alphabétique renvoyé par l'API), jamais par rang
const SERIES_COLORS = ['var(--viz-1)', 'var(--viz-2)', 'var(--viz-3)', 'var(--viz-4)']
const containerSeries = computed(() => (history.value?.containers ?? []).map((c, i) => ({
  key: c.name,
  name: c.name,
  color: SERIES_COLORS[i % SERIES_COLORS.length]!,
  points: c.points,
  current: c.points.at(-1)?.[1] ?? null,
})))
// Échelle fixe 0–100 % (100 % = 1 cœur) pour comparer les fenêtres entre elles ;
// étendue par paliers de 50 si un conteneur dépasse un cœur
const containerMax = computed(() => {
  const max = Math.max(0, ...containerSeries.value.flatMap(s => s.points.map(p => p[1])))
  return Math.max(100, Math.ceil(max / 50) * 50)
})

// Mise en avant d'une série : survol (courbe, étiquette, légende) ou épinglage au clic sur la légende
const hovered = ref<string | null>(null)
const pinned = ref<string | null>(null)
const highlight = computed({
  get: () => hovered.value ?? pinned.value,
  set: (value: string | null) => { hovered.value = value },
})

// --- Classement mémoire
const topMemory = computed(() => all.value
  .filter(c => c.memory != null)
  .sort((a, b) => b.memory! - a.memory!)
  .slice(0, 6)
  .map(c => ({ label: c.name, value: c.memory!, display: formatBytes(c.memory) })))
</script>

<template>
  <UDashboardPanel id="overview">
    <template #header>
      <PageNavbar title="Vue d'ensemble" />
    </template>

    <template #body>
      <StaleNotice />

      <!-- Indicateurs : un clic filtre la liste des conteneurs ci-dessous -->
      <section aria-label="Indicateurs" class="grid shrink-0 grid-cols-2 gap-3 sm:grid-cols-3 xl:grid-cols-5">
        <StatTile
          v-for="tile in tiles"
          :key="tile.key"
          :label="tile.label"
          :value="tile.value"
          :total="tile.total"
          :icon="tile.icon"
          :hint="tile.hint"
          :status="tile.status"
          :link="tile.link"
          :pressed="filter === tile.key"
          @toggle="toggleFilter(tile.key)"
        />
      </section>

      <!-- Conteneurs (2/3) et ressources de l'hôte (1/3) -->
      <div class="grid shrink-0 items-start gap-4 xl:grid-cols-3">
        <div class="min-w-0 xl:col-span-2">
          <ContainerList :filter="filter" @clear-filter="filter = null" />
        </div>

        <div class="flex min-w-0 flex-col gap-4">
          <HostResources />
          <UCard :ui="{ header: 'px-4 py-3 sm:px-4', body: 'px-4 py-3 sm:px-4 sm:py-3' }">
            <template #header>
              <h3 class="font-semibold">Mémoire par conteneur</h3>
            </template>
            <BarList :items="topMemory" />
          </UCard>
        </div>
      </div>

      <!-- Activité : trois graphiques empilés sur le même axe de temps -->
      <UCard as="section" aria-labelledby="activity-title" class="shrink-0">
        <template #header>
          <div class="flex flex-wrap items-center justify-between gap-2">
            <h3 id="activity-title" class="font-semibold">Activité</h3>
            <div class="flex flex-wrap items-center gap-2">
              <UTabs v-model="range" :items="RANGES" :content="false" size="xs" color="neutral" aria-label="Période des courbes" />
              <UButton
                v-if="isLive"
                :icon="paused || globalPaused ? 'i-lucide-play' : 'i-lucide-pause'"
                :label="globalPaused ? 'Actualisation en pause' : paused ? 'En pause' : 'En direct'"
                :color="paused || globalPaused ? 'neutral' : 'success'"
                :disabled="globalPaused"
                :aria-pressed="paused"
                variant="soft"
                size="xs"
                @click="paused = !paused"
              >
                <template v-if="!paused && !globalPaused" #leading>
                  <span class="relative flex size-2" aria-hidden="true">
                    <span class="absolute inline-flex size-full animate-ping rounded-full bg-success opacity-75" />
                    <span class="relative inline-flex size-2 rounded-full bg-success" />
                  </span>
                </template>
              </UButton>
            </div>
          </div>
        </template>

        <div v-if="hasData" class="flex flex-col gap-3">
          <div>
            <h4 class="mb-1 text-xs font-medium text-muted">CPU de l'hôte</h4>
            <TimeChart
              v-model:hover-time="hoverTime"
              label="CPU de l'hôte"
              :series="hostCpu"
              :domain="domain"
              :height="90"
              :pending="historyStatus === 'pending'"
              area
            />
          </div>
          <div>
            <h4 class="mb-1 text-xs font-medium text-muted">Mémoire de l'hôte</h4>
            <TimeChart
              v-model:hover-time="hoverTime"
              label="Mémoire de l'hôte"
              :series="hostMemory"
              :domain="domain"
              :height="90"
              :show-x-axis="!containerSeries.length"
              :pending="historyStatus === 'pending'"
              area
            />
          </div>
          <div>
            <div class="mb-1 flex flex-wrap items-center justify-between gap-x-4 gap-y-1">
              <h4 class="text-xs font-medium text-muted">
                CPU des conteneurs les plus actifs <span class="font-normal">(100 % = 1 cœur)</span>
              </h4>
              <!-- Légende : survol ou focus met la série en avant, clic l'épingle -->
              <ul class="flex flex-wrap gap-1 text-xs">
                <li v-for="s in containerSeries" :key="s.key">
                  <button
                    type="button"
                    class="flex items-center gap-1.5 rounded px-1.5 py-0.5 transition-opacity hover:bg-elevated focus-visible:outline-2 focus-visible:outline-primary"
                    :class="{ 'opacity-50': highlight && highlight !== s.key, 'bg-elevated': pinned === s.key }"
                    :aria-pressed="pinned === s.key"
                    :aria-label="`${s.name} : ${formatPercent(s.current)}. Mettre en avant`"
                    @mouseenter="hovered = s.key"
                    @mouseleave="hovered = null"
                    @focus="hovered = s.key"
                    @blur="hovered = null"
                    @click="pinned = pinned === s.key ? null : s.key"
                  >
                    <span class="h-0.5 w-3 rounded" :style="{ background: s.color }" />
                    <span class="text-default">{{ s.name }}</span>
                    <span class="font-semibold text-highlighted tabular-nums">{{ formatPercent(s.current) }}</span>
                  </button>
                </li>
              </ul>
            </div>
            <TimeChart
              v-if="containerSeries.length"
              v-model:hover-time="hoverTime"
              v-model:highlight="highlight"
              label="CPU des conteneurs les plus actifs"
              :series="containerSeries"
              :domain="domain"
              :y-max="containerMax"
              :height="150"
              :pending="historyStatus === 'pending'"
              show-x-axis
            />
            <p v-else class="text-sm text-muted">Aucun conteneur actif sur la période.</p>
          </div>
          <p class="flex items-center gap-1.5 text-xs text-muted">
            <svg width="16" height="2" aria-hidden="true"><line x1="0" x2="16" y1="1" y2="1" stroke="var(--viz-warning)" stroke-dasharray="4 3" stroke-width="2" /></svg>
            Seuil « élevé » à 80 %
          </p>
        </div>
        <p v-else class="text-sm text-muted">Pas encore de données.</p>
      </UCard>

      <!-- Logs en temps réel -->
      <LogsCard />
    </template>
  </UDashboardPanel>
</template>

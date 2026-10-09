<script setup lang="ts">
import type { TableColumn } from '@nuxt/ui'

const { data, error } = await useContainers()
type Service = NonNullable<typeof data.value>['containers'][number]

const route = useRoute()

const ALL_PROJECTS = 'Tous les projets'
const category = ref<Category | 'all'>('all')
const project = ref(ALL_PROJECTS)
const search = ref('')

// Filtre d'état (?state=running|stopped|unhealthy)
const STATES = [
  { label: 'Tous les états', value: 'all' },
  { label: 'Actifs', value: 'running' },
  { label: 'Arrêtés', value: 'stopped' },
  { label: 'Malades', value: 'unhealthy' },
]
type StateFilter = 'all' | 'running' | 'stopped' | 'unhealthy'
const state = ref<StateFilter>('all')

// Liens profonds : /services?category=app&project=plumo, /services?q=<nom> (recherche globale)
watch(() => route.query, (query) => {
  if (typeof query.q === 'string') {
    search.value = query.q
    category.value = 'all'
  }
  if (typeof query.category === 'string' && (query.category === 'all' || query.category in CATEGORIES)) {
    category.value = query.category as Category | 'all'
  }
  project.value = typeof query.project === 'string' ? query.project : ALL_PROJECTS
  state.value = STATES.some(s => s.value === query.state) ? query.state as StateFilter : 'all'
}, { immediate: true })

const all = computed(() => data.value?.containers ?? [])
const countIn = (cat: Category | 'all') => all.value.filter(c => cat === 'all' || c.category === cat).length

const tabs = computed(() => [
  { label: 'Tout', value: 'all', icon: 'i-lucide-list', badge: countIn('all') },
  ...CATEGORY_KEYS.map(key => ({ label: CATEGORIES[key].label, value: key, icon: CATEGORIES[key].icon, badge: countIn(key) })),
])

// Les projets ne se choisissent que parmi les applications
const appProjects = computed(() => [ALL_PROJECTS, ...new Set(all.value
  .filter(c => c.category === 'app')
  .map(c => c.project ?? 'sans projet'))].sort((a, b) => a === ALL_PROJECTS ? -1 : b === ALL_PROJECTS ? 1 : a.localeCompare(b)))

const services = computed(() => all.value.filter((c) => {
  if (category.value !== 'all' && c.category !== category.value) return false
  if (category.value === 'app' && project.value !== ALL_PROJECTS && (c.project ?? 'sans projet') !== project.value) return false
  if (state.value === 'running' && c.state !== 'running') return false
  if (state.value === 'stopped' && c.state === 'running') return false
  if (state.value === 'unhealthy' && c.health !== 'unhealthy') return false
  const needle = search.value.trim().toLowerCase()
  return !needle || c.name.toLowerCase().includes(needle) || c.image.toLowerCase().includes(needle)
    || (c.project ?? '').toLowerCase().includes(needle)
}))

const runningCount = computed(() => services.value.filter(c => c.state === 'running').length)

const columns: TableColumn<Service>[] = [
  { accessorKey: 'name', header: 'Service' },
  { accessorKey: 'state', header: 'État' },
  { accessorKey: 'image', header: 'Image' },
  { accessorKey: 'cpu', header: 'CPU' },
  { accessorKey: 'memory', header: 'RAM' },
  { accessorKey: 'status', header: 'Depuis' },
  { id: 'actions', header: '' },
]

const stateBadge = containerState

// Actions start / stop / restart, confirmées dans une fenêtre
const actions = useContainerActions()

// Tiroir de détail (activité, logs) du service choisi
const drawer = ref<{ name: string, tab: 'activity' | 'logs' } | null>(null)
const drawerOpen = computed({
  get: () => drawer.value !== null,
  set: (open) => { if (!open) drawer.value = null },
})
const drawerTab = computed({
  get: () => drawer.value?.tab ?? 'activity',
  set: (tab) => { if (drawer.value) drawer.value.tab = tab },
})
</script>

<template>
  <UCard :ui="{ body: 'p-0 sm:p-0' }">
    <template #header>
      <div class="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 class="font-semibold">Services</h2>
          <p class="text-sm text-muted">{{ runningCount }} / {{ services.length }} en cours d'exécution</p>
        </div>
        <div class="flex flex-wrap gap-2">
          <UInput v-model="search" icon="i-lucide-search" placeholder="Filtrer…" class="w-44" />
          <USelect v-if="category === 'app'" v-model="project" :items="appProjects" class="w-48" />
          <USelect v-model="state" :items="STATES" class="w-40" />
        </div>
      </div>
      <UTabs
        v-model="category"
        :items="tabs"
        :content="false"
        variant="link"
        size="sm"
        class="mt-3 -mb-4"
      />
    </template>

    <StaleNotice class="m-4" />
    <UAlert
      v-if="error"
      icon="i-lucide-triangle-alert"
      color="error"
      variant="subtle"
      title="Impossible de lister les conteneurs"
      :description="error.statusMessage"
      class="m-4"
    />
    <UAlert
      v-else-if="data && !data.metricsAvailable"
      icon="i-lucide-triangle-alert"
      color="warning"
      variant="subtle"
      title="Métriques CPU et RAM indisponibles (Prometheus ne répond pas)"
      class="m-4"
    />

    <UTable
      :data="services"
      :columns="columns"
      :loading="!data && !error"
      :ui="{ tr: 'group/row hover:bg-elevated/40' }"
      class="w-full"
    >
      <template #name-cell="{ row }">
        <!-- Nom affiché en entier (colonne large), cliquable quand le service a une interface web -->
        <div class="flex min-w-56 items-center gap-1.5">
          <FavoriteToggle :name="row.original.name" class="-ml-1.5" />
          <ULink
            v-if="row.original.url"
            :to="row.original.url"
            target="_blank"
            class="group inline-flex items-center gap-1 rounded-sm font-medium text-highlighted underline-offset-4 hover:text-primary hover:underline focus-visible:outline-2 focus-visible:outline-primary"
            :title="`Ouvrir ${row.original.url}`"
          >
            {{ row.original.name }}
            <UIcon name="i-lucide-external-link" class="size-3.5 text-muted group-hover:text-primary" />
          </ULink>
          <span v-else class="font-medium">{{ row.original.name }}</span>
          <span v-if="row.original.ports.length" class="font-mono text-xs text-muted" title="Ports publiés sur l'hôte">
            {{ row.original.ports.map(p => `:${p.host}${p.type === 'tcp' ? '' : `/${p.type}`}`).join(' ') }}
          </span>
        </div>
        <div class="mt-0.5 flex items-center gap-1.5 pl-6">
          <UBadge
            v-if="category === 'all'"
            :color="CATEGORIES[row.original.category].color"
            :icon="CATEGORIES[row.original.category].icon"
            variant="soft"
            size="sm"
          >
            {{ CATEGORIES[row.original.category].label }}
          </UBadge>
          <span v-if="row.original.category === 'app'" class="text-xs text-muted">{{ row.original.project ?? 'sans projet' }}</span>
        </div>
      </template>

      <template #state-cell="{ row }">
        <UBadge :color="stateBadge(row.original).color" :variant="stateBadge(row.original).color === 'error' || stateBadge(row.original).color === 'warning' ? 'solid' : 'subtle'">
          {{ stateBadge(row.original).label }}
        </UBadge>
      </template>

      <template #image-cell="{ row }">
        <span class="font-mono text-xs text-muted">{{ row.original.image }}</span>
      </template>

      <template #cpu-cell="{ row }">
        <span class="tabular-nums">{{ formatPercent(row.original.cpu) }}</span>
      </template>

      <template #memory-cell="{ row }">
        <span class="tabular-nums">{{ formatBytes(row.original.memory) }}</span>
      </template>

      <template #status-cell="{ row }">
        <span class="text-xs text-muted">{{ row.original.status }}</span>
      </template>

      <template #actions-cell="{ row }">
        <ContainerQuickActions
          :container="row.original"
          :actions="actions"
          activity
          @open="(tab) => drawer = { name: row.original.name, tab }"
        />
      </template>
    </UTable>

    <ServiceDrawer
      v-if="drawer"
      v-model:open="drawerOpen"
      v-model:tab="drawerTab"
      :name="drawer.name"
    />

    <ContainerActionModal :actions="actions" />
  </UCard>
</template>

<script setup lang="ts">
import type { TableColumn } from '@nuxt/ui'

type Action = 'start' | 'stop' | 'restart'

const { data, error } = await useContainers()
type Service = NonNullable<typeof data.value>['containers'][number]

const toast = useToast()
const route = useRoute()

const ALL_PROJECTS = 'Tous les projets'
const category = ref<Category | 'all'>('all')
const project = ref(ALL_PROJECTS)
const search = ref('')

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

function stateBadge(service: Service) {
  if (service.state === 'running') {
    if (service.health === 'unhealthy') return { label: 'malade', color: 'error' as const }
    if (service.health === 'starting') return { label: 'démarrage', color: 'warning' as const }
    return { label: service.health === 'healthy' ? 'sain' : 'actif', color: 'success' as const }
  }
  if (service.state === 'restarting') return { label: 'redémarre', color: 'warning' as const }
  if (service.state === 'paused') return { label: 'en pause', color: 'warning' as const }
  if (service.state === 'dead') return { label: 'mort', color: 'error' as const }
  return { label: service.onDemand ? 'à la demande' : 'arrêté', color: 'neutral' as const }
}

const ACTION_LABELS: Record<Action, { verb: string, done: string }> = {
  start: { verb: 'Démarrer', done: 'démarré' },
  stop: { verb: 'Arrêter', done: 'arrêté' },
  restart: { verb: 'Redémarrer', done: 'redémarré' },
}

// Action en attente de confirmation, puis action en cours par conteneur
const pending = ref<{ service: Service, action: Action } | null>(null)
const running = ref<Record<string, Action>>({})
const confirmOpen = computed({
  get: () => pending.value !== null,
  set: (open) => { if (!open) pending.value = null },
})

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

async function confirmAction() {
  if (!pending.value) return
  const { service, action } = pending.value
  pending.value = null
  running.value[service.name] = action
  const failure = await postAction(`/api/containers/${encodeURIComponent(service.name)}/${action}`)
  if (failure) {
    toast.add({ title: `Échec : ${ACTION_LABELS[action].verb.toLowerCase()} ${service.name}`, description: failure, color: 'error', icon: 'i-lucide-circle-x' })
  } else {
    toast.add({ title: `${service.name} ${ACTION_LABELS[action].done}`, color: 'success', icon: 'i-lucide-circle-check' })
  }
  delete running.value[service.name]
  await refreshNuxtData('containers')
}
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

    <UTable :data="services" :columns="columns" :loading="!data && !error" class="w-full">
      <template #name-cell="{ row }">
        <div class="flex items-center gap-1.5">
          <span class="font-medium">{{ row.original.name }}</span>
          <UButton
            v-if="row.original.url"
            :to="row.original.url"
            target="_blank"
            icon="i-lucide-external-link"
            color="neutral"
            variant="link"
            size="xs"
            :aria-label="`Ouvrir ${row.original.name}`"
          />
        </div>
        <div class="mt-0.5 flex items-center gap-1.5">
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
        <UBadge :color="stateBadge(row.original).color" variant="subtle">
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
        <div class="flex justify-end gap-1">
          <UButton
            icon="i-lucide-chart-line"
            color="neutral"
            variant="ghost"
            size="sm"
            :aria-label="`Activité de ${row.original.name}`"
            @click="drawer = { name: row.original.name, tab: 'activity' }"
          />
          <UButton
            icon="i-lucide-scroll-text"
            color="neutral"
            variant="ghost"
            size="sm"
            :aria-label="`Logs de ${row.original.name}`"
            @click="drawer = { name: row.original.name, tab: 'logs' }"
          />
          <template v-if="row.original.state === 'running'">
            <UButton
              icon="i-lucide-rotate-cw"
              color="neutral"
              variant="ghost"
              size="sm"
              :loading="running[row.original.name] === 'restart'"
              :disabled="!!running[row.original.name]"
              :aria-label="`Redémarrer ${row.original.name}`"
              @click="pending = { service: row.original, action: 'restart' }"
            />
            <UButton
              v-if="!row.original.stopProtected"
              icon="i-lucide-square"
              color="error"
              variant="ghost"
              size="sm"
              :loading="running[row.original.name] === 'stop'"
              :disabled="!!running[row.original.name]"
              :aria-label="`Arrêter ${row.original.name}`"
              @click="pending = { service: row.original, action: 'stop' }"
            />
          </template>
          <UButton
            v-else
            icon="i-lucide-play"
            color="success"
            variant="ghost"
            size="sm"
            :loading="running[row.original.name] === 'start'"
            :disabled="!!running[row.original.name]"
            :aria-label="`Démarrer ${row.original.name}`"
            @click="pending = { service: row.original, action: 'start' }"
          />
        </div>
      </template>
    </UTable>

    <ServiceDrawer
      v-if="drawer"
      v-model:open="drawerOpen"
      v-model:tab="drawerTab"
      :name="drawer.name"
    />

    <UModal
      v-model:open="confirmOpen"
      :title="pending ? `${ACTION_LABELS[pending.action].verb} ${pending.service.name} ?` : ''"
      :description="pending?.action === 'restart' ? 'Le service sera indisponible pendant le redémarrage.' : undefined"
    >
      <template #footer>
        <div class="flex w-full justify-end gap-2">
          <UButton label="Annuler" color="neutral" variant="outline" @click="pending = null" />
          <UButton
            v-if="pending"
            :label="ACTION_LABELS[pending.action].verb"
            :color="pending.action === 'stop' ? 'error' : 'primary'"
            @click="confirmAction"
          />
        </div>
      </template>
    </UModal>
  </UCard>
</template>

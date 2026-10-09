<script setup lang="ts">
// Liste des conteneurs regroupés : favoris, stack, outils, applications par projet
// Compose, puis les autres. Filtrable (catégorie, problèmes, mises à jour) et cherchable.
const props = defineProps<{ filter?: ContainerFilter | null }>()
const emit = defineEmits<{ 'clear-filter': [] }>()

const { data } = await useContainers()
const { data: updates } = useUpdates()
const problems = useProblems()
const { isFavorite } = useFavorites()
type Container = NonNullable<typeof data.value>['containers'][number]

const search = ref('')

// Mises à jour indexées par nom de conteneur (WUD utilise le même nom)
const updateByName = computed(() => new Map((updates.value?.updates ?? []).map(u => [u.name, u])))
const problemNames = computed(() => new Set(problems.value.map(c => c.name)))

function matchesFilter(c: Container) {
  switch (props.filter) {
    case 'stack':
    case 'tools':
    case 'app':
      return c.category === props.filter
    case 'problems':
      return problemNames.value.has(c.name)
    case 'updates':
      return updateByName.value.has(c.name)
    default:
      return true
  }
}

const shown = computed(() => {
  const needle = search.value.trim().toLowerCase()
  return (data.value?.containers ?? []).filter(c => matchesFilter(c) && (!needle
    || c.name.toLowerCase().includes(needle)
    || (c.project ?? '').toLowerCase().includes(needle)
    || c.image.toLowerCase().includes(needle)))
})

interface Group {
  key: string
  label: string
  icon: string
  // Lien vers le tableau complet, filtré sur le groupe
  to?: { path: string, query: Record<string, string> }
  containers: Container[]
  summary: ReturnType<typeof groupSummary> | null
}

const groups = computed<Group[]>(() => {
  const favorites = shown.value.filter(c => isFavorite(c.name))
  const rest = shown.value.filter(c => !isFavorite(c.name))
  const result: Group[] = []

  if (favorites.length) {
    result.push({ key: '~favorites', label: 'Favoris', icon: 'i-lucide-star', containers: favorites, summary: null })
  }
  for (const category of ['stack', 'tools'] as const) {
    const containers = rest.filter(c => c.category === category)
    if (containers.length) {
      result.push({
        key: category,
        label: CATEGORIES[category].label,
        icon: CATEGORIES[category].icon,
        to: { path: '/services', query: { category } },
        containers,
        summary: groupSummary(containers, false),
      })
    }
  }
  const byProject = new Map<string, Container[]>()
  for (const c of rest.filter(c => c.category === 'app')) {
    const key = c.project ?? 'sans projet'
    byProject.set(key, [...(byProject.get(key) ?? []), c])
  }
  for (const [project, containers] of [...byProject].sort(([a], [b]) => a.localeCompare(b))) {
    result.push({
      key: `app:${project}`,
      label: project,
      icon: CATEGORIES.app.icon,
      to: { path: '/services', query: { category: 'app', project } },
      containers,
      summary: groupSummary(containers),
    })
  }
  const others = rest.filter(c => c.category === 'other')
  if (others.length) {
    result.push({
      key: 'other',
      label: CATEGORIES.other.label,
      icon: CATEGORIES.other.icon,
      to: { path: '/services', query: { category: 'other' } },
      containers: others,
      summary: groupSummary(others),
    })
  }
  return result
})

const total = computed(() => data.value?.containers.length ?? 0)

// État affiché seulement quand il sort de l'ordinaire (un conteneur actif ou sain se passe de libellé)
function notableState(c: Container) {
  const state = containerState(c)
  return state.color === 'success' ? null : state
}

const ports = (c: Container) => c.ports.map(p => `:${p.host}${p.type === 'tcp' ? '' : `/${p.type}`}`).join(' ')

function clearAll() {
  search.value = ''
  if (props.filter) emit('clear-filter')
}

// Actions (confirmées) et tiroir de logs, sans quitter la page
const actions = useContainerActions()
const drawer = ref<{ name: string, tab: 'activity' | 'logs' } | null>(null)
const drawerOpen = computed({
  get: () => drawer.value !== null,
  set: (open) => { if (!open) drawer.value = null },
})
const drawerTab = computed({
  get: () => drawer.value?.tab ?? 'logs',
  set: (tab) => { if (drawer.value) drawer.value.tab = tab },
})
</script>

<template>
  <UCard class="flex min-h-0 flex-col" :ui="{ header: 'shrink-0', body: 'min-h-0 flex-1 overflow-y-auto p-0 sm:p-0 max-h-[40rem]' }">
    <template #header>
      <div class="flex flex-wrap items-center justify-between gap-x-3 gap-y-2">
        <div class="flex min-w-0 flex-wrap items-center gap-2">
          <h3 class="flex items-center gap-2 font-semibold">
            <UIcon name="i-lucide-container" /> Conteneurs
          </h3>
          <span class="text-sm text-muted tabular-nums">
            {{ filter || search ? `${shown.length} / ${total}` : total }}
          </span>
          <!-- Filtre actif (posé depuis les tuiles de la vue d'ensemble) : un clic le retire -->
          <UButton
            v-if="filter"
            :label="FILTER_LABELS[filter]"
            trailing-icon="i-lucide-x"
            color="primary"
            variant="soft"
            size="xs"
            class="rounded-full"
            :aria-label="`Retirer le filtre ${FILTER_LABELS[filter]}`"
            @click="emit('clear-filter')"
          />
        </div>
        <div class="flex items-center gap-1">
          <UInput
            v-model="search"
            icon="i-lucide-search"
            placeholder="Rechercher…"
            size="sm"
            class="w-40"
            aria-label="Rechercher un conteneur"
          />
          <UButton
            to="/services"
            icon="i-lucide-table-2"
            color="neutral"
            variant="ghost"
            size="sm"
            aria-label="Tableau complet des services"
            title="Tableau complet des services"
          />
        </div>
      </div>
    </template>

    <div v-if="!groups.length" class="flex flex-col items-center gap-2 p-6 text-center text-sm text-muted">
      <p>{{ data ? 'Aucun conteneur ne correspond.' : 'Chargement…' }}</p>
      <UButton v-if="filter || search" label="Tout afficher" color="neutral" variant="outline" size="xs" @click="clearAll" />
    </div>

    <section v-for="group in groups" :key="group.key" :aria-label="group.label" class="border-b border-default last:border-b-0">
      <!-- En-tête de groupe : nom + micro-indicateur quantitatif (pastille + texte) -->
      <div class="sticky top-0 z-1 flex flex-wrap items-center gap-x-3 gap-y-0.5 bg-elevated/60 px-4 py-1.5 backdrop-blur sm:px-5">
        <h4 class="flex items-center gap-1.5 text-xs font-semibold tracking-wide text-muted uppercase">
          <UIcon :name="group.icon" class="size-3.5" :class="{ 'text-warning': group.key === '~favorites' }" />
          <ULink v-if="group.to" :to="group.to" class="rounded-sm hover:text-highlighted focus-visible:outline-2 focus-visible:outline-primary">
            {{ group.label }}
          </ULink>
          <span v-else>{{ group.label }}</span>
        </h4>
        <span v-if="group.summary" class="flex items-center gap-1.5 text-xs text-muted tabular-nums">
          <span class="size-2 shrink-0 rounded-full" :class="DOT_CLASS[group.summary.color]" aria-hidden="true" />
          {{ group.summary.label }}
        </span>
      </div>

      <ul>
        <li
          v-for="c in group.containers"
          :key="c.name"
          class="group/row flex items-center gap-2 px-2 py-1.5 hover:bg-elevated/40 sm:px-3"
        >
          <FavoriteToggle :name="c.name" />

          <div class="min-w-48 flex-1 max-sm:min-w-0">
            <div class="flex flex-wrap items-baseline gap-x-2">
              <!-- Nom affiché en entier, cliquable quand le service a une interface web -->
              <ULink
                v-if="c.url"
                :to="c.url"
                target="_blank"
                class="group/link inline-flex items-center gap-1 rounded-sm text-sm font-medium text-highlighted underline-offset-4 hover:text-primary hover:underline focus-visible:outline-2 focus-visible:outline-primary max-sm:break-all"
                :title="`Ouvrir ${c.url}`"
              >
                {{ c.name }}
                <UIcon name="i-lucide-external-link" class="size-3 shrink-0 text-muted group-hover/link:text-primary" />
              </ULink>
              <span v-else class="text-sm font-medium text-highlighted max-sm:break-all">{{ c.name }}</span>
              <span v-if="c.ports.length" class="font-mono text-xs text-muted" title="Ports publiés sur l'hôte">{{ ports(c) }}</span>
            </div>
            <!-- Sous le nom : l'état seulement quand il sort de l'ordinaire, et les mises à jour -->
            <div v-if="notableState(c) || updateByName.has(c.name)" class="flex flex-wrap items-center gap-x-3 text-xs">
              <span
                v-if="notableState(c)"
                class="flex items-center gap-1"
                :class="notableState(c)!.color === 'error' ? 'text-error' : 'text-muted'"
              >
                <span class="size-1.5 rounded-full" :class="DOT_CLASS[notableState(c)!.color]" aria-hidden="true" />
                {{ notableState(c)!.label }}
              </span>
              <span
                v-if="updateByName.has(c.name)"
                class="flex items-center gap-1 text-muted"
                :title="`${updateByName.get(c.name)!.current} → ${updateByName.get(c.name)!.next}`"
              >
                <UIcon name="i-lucide-circle-arrow-up" class="size-3 text-info" />
                mise à jour : {{ updateByName.get(c.name)!.next }}
              </span>
            </div>
          </div>

          <div class="hidden w-28 shrink-0 justify-end gap-3 text-xs text-muted tabular-nums md:flex">
            <span title="CPU">{{ formatPercent(c.cpu) }}</span>
            <span title="Mémoire">{{ formatBytes(c.memory) }}</span>
          </div>

          <ContainerQuickActions :container="c" :actions="actions" @open="(tab) => drawer = { name: c.name, tab }" />
        </li>
      </ul>
    </section>

    <ServiceDrawer v-if="drawer" v-model:open="drawerOpen" v-model:tab="drawerTab" :name="drawer.name" />
    <ContainerActionModal :actions="actions" />
  </UCard>
</template>

<script setup lang="ts">
import type { CommandPaletteGroup, CommandPaletteItem, NavigationMenuItem } from '@nuxt/ui'

const { data: containers } = await useContainers()
const { data: updates } = await useUpdates()
const { data: vulnerabilities } = await useVulnerabilities()
const lastRefresh = useLastRefresh()

const all = computed(() => containers.value?.containers ?? [])

// Problèmes de toutes les catégories (stack, outils, applications malades)
const problems = useProblems()
const problemCount = computed(() => problems.value.length)
const paused = useRefreshPaused()

// Vulnérabilités critiques, toutes images confondues
const criticalCount = computed(() => vulnerabilities.value?.available
  ? vulnerabilities.value.images.reduce((sum, image) => sum + image.counts.CRITICAL, 0)
  : 0)

const navigation = computed<NavigationMenuItem[]>(() => [
  { label: 'Vue d\'ensemble', icon: 'i-lucide-layout-dashboard', to: '/' },
  {
    label: 'Services',
    icon: 'i-lucide-boxes',
    to: '/services',
    badge: problemCount.value ? { label: String(problemCount.value), color: 'error', variant: 'subtle' } : undefined,
  },
  {
    label: 'Mises à jour',
    icon: 'i-lucide-package',
    to: '/mises-a-jour',
    badge: updates.value?.updates.length || undefined,
  },
  { label: 'Sauvegardes', icon: 'i-lucide-archive', to: '/sauvegardes' },
  {
    label: 'Vulnérabilités',
    icon: 'i-lucide-shield-alert',
    to: '/vulnerabilites',
    badge: criticalCount.value ? { label: String(criticalCount.value), color: 'error', variant: 'subtle' } : undefined,
  },
])

// Liens vers les interfaces des outils de la stack, déduits des labels Traefik
const TOOL_ICONS: Record<string, string> = {
  grafana: 'i-lucide-chart-line',
  prometheus: 'i-lucide-flame',
  wud: 'i-lucide-package-check',
  portainer: 'i-lucide-ship',
  dozzle: 'i-lucide-scroll-text',
  traefik: 'i-lucide-route',
  mailer: 'i-lucide-mail',
  adminer: 'i-lucide-database',
  glance: 'i-lucide-panels-top-left',
  organizr: 'i-lucide-layout-grid',
  'it-tools': 'i-lucide-wrench',
  tinyauth: 'i-lucide-key-round',
  hoppscotch: 'i-lucide-send',
  wiremock: 'i-lucide-drama',
  healthchecks: 'i-lucide-heart-pulse',
  dockge: 'i-lucide-square-stack',
}
const links = (category: Category) => all.value
  .filter(c => c.category === category && c.url && c.name !== 'dashboard')
  .map(c => ({
    label: c.name,
    icon: TOOL_ICONS[c.name] ?? 'i-lucide-external-link',
    to: c.url!,
    target: '_blank',
  }))
const stackLinks = computed(() => links('stack'))
const toolLinks = computed(() => links('tools'))

// Applications : un lien par projet Compose, vers la page Services filtrée
const appProjects = computed<NavigationMenuItem[]>(() => {
  const projects = new Map<string, { running: number, total: number, unhealthy: number }>()
  for (const c of all.value.filter(c => c.category === 'app')) {
    const key = c.project ?? 'sans projet'
    const entry = projects.get(key) ?? { running: 0, total: 0, unhealthy: 0 }
    entry.total++
    if (c.state === 'running') entry.running++
    if (c.health === 'unhealthy') entry.unhealthy++
    projects.set(key, entry)
  }
  return [...projects].sort(([a], [b]) => a.localeCompare(b)).map(([name, count]) => ({
    label: name,
    icon: 'i-lucide-app-window',
    to: { path: '/services', query: { category: 'app', project: name } },
    exactQuery: true,
    slot: 'project' as const,
    // Badge cliquable : filtre la liste sur les conteneurs en cause
    badge: {
      label: `${count.running}/${count.total}`,
      color: count.unhealthy ? 'error' : count.running < count.total ? 'warning' : 'neutral',
      variant: count.unhealthy || count.running < count.total ? 'subtle' : 'outline',
    },
    state: count.unhealthy ? 'unhealthy' : count.running < count.total ? 'stopped' : 'all',
  }))
})

// Le slot personnalisé ne connaît pas le type des éléments : on le rétablit ici
type ProjectItem = NavigationMenuItem & { state: string }
const asProject = (item: unknown) => item as ProjectItem

function filterProject(item: ProjectItem) {
  navigateTo({ path: '/services', query: { category: 'app', project: item.label, state: item.state } })
}

// Menu secondaire : une section repliable par catégorie
const sections = computed<NavigationMenuItem[]>(() => [
  { label: CATEGORIES.app.label, icon: CATEGORIES.app.icon, defaultOpen: true, children: appProjects.value },
  { label: CATEGORIES.tools.label, icon: CATEGORIES.tools.icon, defaultOpen: true, children: toolLinks.value },
  { label: CATEGORIES.stack.label, icon: CATEGORIES.stack.icon, defaultOpen: false, children: stackLinks.value },
].filter(section => section.children.length))

// Recherche globale (⌘K) : pages, puis services groupés par catégorie
const searchGroups = computed<CommandPaletteGroup<CommandPaletteItem>[]>(() => [
  {
    id: 'pages',
    label: 'Pages',
    items: navigation.value.map(item => ({ label: item.label, icon: item.icon, to: item.to as string })),
  },
  ...CATEGORY_KEYS.map(key => ({
    id: key,
    label: CATEGORIES[key].label,
    items: all.value.filter(c => c.category === key).map(c => ({
      label: c.name,
      suffix: key === 'app' ? c.project ?? undefined : undefined,
      description: c.image,
      icon: c.state === 'running' ? 'i-lucide-circle-check' : 'i-lucide-circle-stop',
      to: { path: '/services', query: { q: c.name } },
    })),
  })),
  { id: 'links', label: 'Ouvrir un outil', items: [...toolLinks.value, ...stackLinks.value] },
])

// Services et hôte toutes les 10 s, mises à jour et sauvegardes toutes les minutes
let tick = 0
let timer: ReturnType<typeof setInterval> | undefined
onMounted(() => {
  timer = setInterval(async () => {
    tick++
    if (paused.value) return
    await refreshNuxtData(tick % 6 === 0 ? ALL_REFRESH : FAST_REFRESH)
    lastRefresh.value = new Date()
  }, FAST_REFRESH_MS)
})
onBeforeUnmount(() => clearInterval(timer))
</script>

<template>
  <UDashboardGroup unit="rem">
    <UDashboardSidebar
      collapsible
      resizable
      :default-size="15"
      :min-size="12"
      :max-size="20"
      :ui="{ footer: 'border-t border-default' }"
    >
      <template #header="{ collapsed }">
        <NuxtLink to="/" class="flex items-center gap-2">
          <UIcon name="i-lucide-container" class="size-6 shrink-0 text-primary" />
          <span v-if="!collapsed" class="truncate font-semibold">Docker Master</span>
        </NuxtLink>
      </template>

      <template #default="{ collapsed }">
        <UNavigationMenu :items="navigation" :collapsed="collapsed" orientation="vertical" tooltip />

        <USeparator />
        <UNavigationMenu :items="sections" :collapsed="collapsed" orientation="vertical" tooltip popover>
          <template #project-trailing="{ item }">
            <UBadge
              v-bind="asProject(item).badge as object"
              size="sm"
              role="button"
              tabindex="0"
              class="cursor-pointer tabular-nums hover:ring-2 hover:ring-primary/50"
              :title="asProject(item).state === 'all' ? 'Voir les conteneurs' : asProject(item).state === 'unhealthy' ? 'Voir les conteneurs malades' : 'Voir les conteneurs arrêtés'"
              @click.prevent.stop="filterProject(asProject(item))"
              @keydown.enter.prevent.stop="filterProject(asProject(item))"
            />
          </template>
        </UNavigationMenu>
      </template>

      <template #footer="{ collapsed }">
        <div class="flex w-full items-center justify-between gap-2" :class="{ 'flex-col': collapsed }">
          <span v-if="!collapsed" class="truncate text-xs text-muted">
            <template v-if="paused"><UIcon name="i-lucide-pause" class="text-warning" /> Actualisation en pause</template>
            <template v-else>Actualisé à {{ lastRefresh.toLocaleTimeString('fr-FR') }}</template>
          </span>
          <UColorModeButton />
        </div>
      </template>
    </UDashboardSidebar>

    <UDashboardSearch :groups="searchGroups" placeholder="Rechercher un service, une page, un outil…" />

    <slot />
  </UDashboardGroup>
</template>

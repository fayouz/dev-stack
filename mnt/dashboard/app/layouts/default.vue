<script setup lang="ts">
import type { CommandPaletteGroup, CommandPaletteItem, NavigationMenuItem } from '@nuxt/ui'

const config = useRuntimeConfig()
const { data: containers } = await useContainers()
const { data: updates } = await useUpdates()
const lastRefresh = useLastRefresh()

const problemCount = computed(() => (containers.value?.containers ?? [])
  .filter(c => c.project === config.public.defaultProject && (c.state !== 'running' || c.health === 'unhealthy'))
  .length)

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
}
const tools = computed(() => (containers.value?.containers ?? [])
  .filter(c => c.url && c.project === config.public.defaultProject && c.name !== 'dashboard')
  .map(c => ({
    label: c.name,
    icon: TOOL_ICONS[c.name] ?? 'i-lucide-external-link',
    to: c.url!,
    target: '_blank',
  })))

// Recherche globale (⌘K) : pages, services et outils
const searchGroups = computed<CommandPaletteGroup<CommandPaletteItem>[]>(() => [
  {
    id: 'pages',
    label: 'Pages',
    items: navigation.value.map(item => ({ label: item.label, icon: item.icon, to: item.to as string })),
  },
  {
    id: 'services',
    label: 'Services',
    items: (containers.value?.containers ?? []).map(c => ({
      label: c.name,
      suffix: c.project ?? undefined,
      description: c.image,
      icon: c.state === 'running' ? 'i-lucide-circle-check' : 'i-lucide-circle-stop',
      to: { path: '/services', query: { q: c.name } },
    })),
  },
  { id: 'tools', label: 'Outils', items: tools.value },
])

// Services et hôte toutes les 5 s, mises à jour et sauvegardes toutes les minutes
let tick = 0
let timer: ReturnType<typeof setInterval> | undefined
onMounted(() => {
  timer = setInterval(async () => {
    tick++
    await refreshNuxtData(tick % 12 === 0 ? ALL_REFRESH : FAST_REFRESH)
    lastRefresh.value = new Date()
  }, 5_000)
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

        <div class="mt-auto">
          <p v-if="!collapsed" class="mb-1 px-2.5 text-xs font-medium text-muted">Outils</p>
          <UNavigationMenu :items="tools" :collapsed="collapsed" orientation="vertical" tooltip />
        </div>
      </template>

      <template #footer="{ collapsed }">
        <div class="flex w-full items-center justify-between gap-2" :class="{ 'flex-col': collapsed }">
          <span v-if="!collapsed" class="truncate text-xs text-muted">
            Actualisé à {{ lastRefresh.toLocaleTimeString('fr-FR') }}
          </span>
          <UColorModeButton />
        </div>
      </template>
    </UDashboardSidebar>

    <UDashboardSearch :groups="searchGroups" placeholder="Rechercher un service, une page, un outil…" />

    <slot />
  </UDashboardGroup>
</template>

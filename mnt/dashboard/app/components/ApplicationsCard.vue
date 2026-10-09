<script setup lang="ts">
import type { DropdownMenuItem } from '@nuxt/ui'

// Résumé des applications en développement : un projet Compose par ligne
const { data } = await useContainers()
type Container = NonNullable<typeof data.value>['containers'][number]

// Actions rapides sans quitter la page : logs (tiroir), redémarrer, arrêter / démarrer
const actions = useContainerActions()
const drawer = ref<string | null>(null)
const drawerTab = ref<'activity' | 'logs'>('logs')
const drawerOpen = computed({
  get: () => drawer.value !== null,
  set: (open) => { if (!open) drawer.value = null },
})

function menu(containers: Container[]): DropdownMenuItem[][] {
  return containers.map(c => [
    { type: 'label' as const, label: c.name, icon: c.state === 'running' ? 'i-lucide-circle-check' : 'i-lucide-circle-stop' },
    { label: 'Logs', icon: 'i-lucide-scroll-text', onSelect: () => { drawerTab.value = 'logs'; drawer.value = c.name } },
    ...(c.state === 'running'
      ? [
          { label: 'Redémarrer', icon: 'i-lucide-rotate-cw', disabled: !!actions.running.value[c.name], onSelect: () => { actions.pending.value = { name: c.name, action: 'restart' } } },
          ...(c.stopProtected ? [] : [{ label: 'Arrêter', icon: 'i-lucide-square', color: 'error' as const, disabled: !!actions.running.value[c.name], onSelect: () => { actions.pending.value = { name: c.name, action: 'stop' } } }]),
        ]
      : [{ label: 'Démarrer', icon: 'i-lucide-play', disabled: !!actions.running.value[c.name], onSelect: () => { actions.pending.value = { name: c.name, action: 'start' } } }]),
  ])
}

const projects = computed(() => {
  const byProject = new Map<string, NonNullable<typeof data.value>['containers']>()
  for (const c of (data.value?.containers ?? []).filter(c => c.category === 'app')) {
    const key = c.project ?? 'sans projet'
    byProject.set(key, [...(byProject.get(key) ?? []), c])
  }
  return [...byProject].sort(([a], [b]) => a.localeCompare(b)).map(([name, containers]) => {
    const running = containers.filter(c => c.state === 'running')
    const unhealthy = running.filter(c => c.health === 'unhealthy').length
    return {
      name,
      containers,
      busy: containers.some(c => actions.running.value[c.name]),
      total: containers.length,
      running: running.length,
      unhealthy,
      cpu: running.reduce((sum, c) => sum + (c.cpu ?? 0), 0),
      memory: running.reduce((sum, c) => sum + (c.memory ?? 0), 0),
      urls: containers.filter(c => c.url).map(c => ({ name: c.name, url: c.url! })),
      // Ports publiés sur l'hôte (la plupart des applications passent par Traefik et n'en ont pas)
      ports: [...new Set(containers.flatMap(c => c.ports.map(p => p.type === 'tcp' ? `${p.host}` : `${p.host}/${p.type}`)))],
      // Libellé explicite : « malade » = au moins un conteneur en cours d'exécution dont le healthcheck échoue
      status: unhealthy
        ? { label: `${unhealthy} malade${unhealthy > 1 ? 's' : ''} · ${running.length}/${containers.length} actifs`, color: 'error' as const, icon: 'i-lucide-circle-x' }
        : running.length === containers.length
          ? { label: `en ligne · ${running.length}/${containers.length}`, color: 'success' as const, icon: 'i-lucide-circle-check' }
          : running.length
            ? { label: `partiel · ${running.length}/${containers.length} actifs`, color: 'warning' as const, icon: 'i-lucide-circle-alert' }
            : { label: `arrêtée · 0/${containers.length}`, color: 'neutral' as const, icon: 'i-lucide-circle-stop' },
    }
  })
})
</script>

<template>
  <UCard class="shrink-0" :ui="{ body: 'p-0 sm:p-0' }">
    <template #header>
      <div class="flex items-center justify-between gap-2">
        <div>
          <h3 class="flex items-center gap-2 font-semibold">
            <UIcon :name="CATEGORIES.app.icon" /> Applications
          </h3>
          <p class="text-sm text-muted">{{ CATEGORIES.app.description }}</p>
        </div>
        <UButton
          :to="{ path: '/services', query: { category: 'app' } }"
          label="Tous les conteneurs"
          trailing-icon="i-lucide-arrow-right"
          color="neutral"
          variant="ghost"
          size="sm"
        />
      </div>
    </template>

    <p v-if="!projects.length" class="p-4 text-sm text-muted">Aucune application détectée.</p>
    <ul v-else class="divide-y divide-default">
      <li v-for="project in projects" :key="project.name" class="flex flex-wrap items-center gap-x-6 gap-y-2 px-4 py-3 sm:px-6">
        <ULink
          :to="{ path: '/services', query: { category: 'app', project: project.name } }"
          class="min-w-40 flex-1 font-medium text-highlighted hover:text-primary"
        >
          {{ project.name }}
          <span v-if="project.ports.length" class="ml-2 font-mono text-xs font-normal text-muted" title="Ports publiés sur l'hôte">
            {{ project.ports.map(p => `:${p}`).join(' ') }}
          </span>
        </ULink>

        <!-- Problèmes en solide (contraste fort), états normaux en léger -->
        <UBadge
          :color="project.status.color"
          :icon="project.status.icon"
          :variant="project.status.color === 'error' || project.status.color === 'warning' ? 'solid' : 'subtle'"
          class="min-w-36 justify-center"
          :title="project.unhealthy ? 'Au moins un conteneur tourne mais son healthcheck échoue' : undefined"
        >
          {{ project.status.label }}
        </UBadge>

        <div class="flex w-44 gap-4 text-sm tabular-nums text-muted">
          <span title="CPU">{{ formatPercent(project.running ? project.cpu : null) }}</span>
          <span title="Mémoire">{{ formatBytes(project.running ? project.memory : null) }}</span>
        </div>

        <div class="flex min-w-32 flex-wrap justify-end gap-1">
          <UButton
            v-for="link in project.urls"
            :key="link.url"
            :to="link.url"
            target="_blank"
            :label="link.name"
            trailing-icon="i-lucide-external-link"
            color="neutral"
            variant="outline"
            size="xs"
          />
          <UDropdownMenu :items="menu(project.containers)" :content="{ align: 'end' }">
            <UButton
              icon="i-lucide-ellipsis-vertical"
              color="neutral"
              variant="ghost"
              size="xs"
              :loading="project.busy"
              :aria-label="`Actions sur ${project.name}`"
            />
          </UDropdownMenu>
        </div>
      </li>
    </ul>

    <ServiceDrawer v-if="drawer" v-model:open="drawerOpen" v-model:tab="drawerTab" :name="drawer" />
    <ContainerActionModal :actions="actions" />
  </UCard>
</template>

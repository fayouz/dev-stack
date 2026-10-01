<script setup lang="ts">
// Résumé des applications en développement : un projet Compose par ligne
const { data } = await useContainers()

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
      total: containers.length,
      running: running.length,
      unhealthy,
      cpu: running.reduce((sum, c) => sum + (c.cpu ?? 0), 0),
      memory: running.reduce((sum, c) => sum + (c.memory ?? 0), 0),
      urls: containers.filter(c => c.url).map(c => ({ name: c.name, url: c.url! })),
      status: unhealthy
        ? { label: 'malade', color: 'error' as const, icon: 'i-lucide-circle-x' }
        : running.length === containers.length
          ? { label: 'en ligne', color: 'success' as const, icon: 'i-lucide-circle-check' }
          : running.length
            ? { label: 'partiel', color: 'warning' as const, icon: 'i-lucide-circle-alert' }
            : { label: 'arrêtée', color: 'neutral' as const, icon: 'i-lucide-circle-stop' },
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
        </ULink>

        <UBadge :color="project.status.color" :icon="project.status.icon" variant="subtle" class="w-28 justify-center">
          {{ project.status.label }} · {{ project.running }}/{{ project.total }}
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
        </div>
      </li>
    </ul>
  </UCard>
</template>

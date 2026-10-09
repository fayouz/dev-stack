<script setup lang="ts">
defineProps<{ title: string }>()

const lastRefresh = useLastRefresh()
const paused = useRefreshPaused()
const problems = useProblems()
const refreshing = ref(false)

async function refresh() {
  refreshing.value = true
  await refreshNuxtData(ALL_REFRESH)
  lastRefresh.value = new Date()
  refreshing.value = false
}

// Thème : clair, sombre ou celui du système (préférence mémorisée par @nuxtjs/color-mode)
const colorMode = useColorMode()
const THEMES = [
  { value: 'light', label: 'Clair', icon: 'i-lucide-sun' },
  { value: 'dark', label: 'Sombre', icon: 'i-lucide-moon' },
  { value: 'system', label: 'Système', icon: 'i-lucide-monitor' },
]
const theme = computed(() => THEMES.find(t => t.value === colorMode.preference) ?? THEMES[2]!)
const themeItems = computed(() => THEMES.map(t => ({
  label: t.label,
  icon: t.icon,
  type: 'checkbox' as const,
  checked: colorMode.preference === t.value,
  onSelect: () => { colorMode.preference = t.value },
})))

function reason(c: typeof problems.value[number]) {
  if (c.health === 'unhealthy') return 'malade (healthcheck en échec)'
  if (c.state === 'restarting') return 'redémarre en boucle'
  return c.state === 'dead' ? 'mort' : 'arrêté'
}
</script>

<template>
  <UDashboardNavbar :title="title">
    <template #leading>
      <UDashboardSidebarCollapse />
    </template>
    <template #right>
      <UDashboardSearchButton label="Rechercher…" class="w-40 sm:w-64" />

      <!-- Alertes : services en erreur, visibles depuis toutes les pages -->
      <UPopover>
        <UChip :show="problems.length > 0" :text="problems.length" color="error" size="3xl" inset>
          <UButton
            :icon="problems.length ? 'i-lucide-bell-ring' : 'i-lucide-bell'"
            :color="problems.length ? 'error' : 'neutral'"
            variant="ghost"
            :aria-label="problems.length ? `${problems.length} problème(s)` : 'Aucun problème'"
          />
        </UChip>
        <template #content>
          <div class="w-80 p-2">
            <p v-if="!problems.length" class="flex items-center gap-2 p-2 text-sm text-muted">
              <UIcon name="i-lucide-circle-check" class="text-success" /> Aucun problème détecté
            </p>
            <ul v-else class="flex flex-col">
              <li v-for="c in problems" :key="c.name">
                <ULink
                  :to="{ path: '/services', query: { q: c.name } }"
                  class="flex items-start gap-2 rounded-md p-2 text-sm hover:bg-elevated"
                >
                  <UIcon name="i-lucide-circle-x" class="mt-0.5 shrink-0 text-error" />
                  <span class="min-w-0">
                    <span class="block truncate font-medium text-highlighted">{{ c.name }}</span>
                    <span class="block text-xs text-muted">{{ CATEGORIES[c.category].label }}{{ c.project && c.category === 'app' ? ` · ${c.project}` : '' }} · {{ reason(c) }}</span>
                  </span>
                </ULink>
              </li>
            </ul>
          </div>
        </template>
      </UPopover>

      <UDropdownMenu :items="themeItems" :content="{ align: 'end' }">
        <UButton
          :icon="theme.icon"
          color="neutral"
          variant="ghost"
          :aria-label="`Thème : ${theme.label}. Changer de thème`"
          :title="`Thème : ${theme.label}`"
        />
      </UDropdownMenu>

      <UButton
        :icon="paused ? 'i-lucide-play' : 'i-lucide-pause'"
        :label="paused ? 'En pause' : undefined"
        :color="paused ? 'warning' : 'neutral'"
        :variant="paused ? 'solid' : 'ghost'"
        :aria-label="paused ? 'Reprendre l\'actualisation automatique' : 'Mettre en pause l\'actualisation automatique'"
        :title="paused ? 'Reprendre l\'actualisation automatique' : 'Mettre en pause l\'actualisation automatique'"
        @click="paused = !paused"
      />
      <UButton
        icon="i-lucide-refresh-cw"
        color="neutral"
        variant="ghost"
        aria-label="Actualiser"
        :loading="refreshing"
        @click="refresh"
      />
    </template>
  </UDashboardNavbar>
</template>

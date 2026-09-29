<script setup lang="ts">
defineProps<{ title: string }>()

const lastRefresh = useLastRefresh()
const refreshing = ref(false)

async function refresh() {
  refreshing.value = true
  await refreshNuxtData(ALL_REFRESH)
  lastRefresh.value = new Date()
  refreshing.value = false
}
</script>

<template>
  <UDashboardNavbar :title="title">
    <template #leading>
      <UDashboardSidebarCollapse />
    </template>
    <template #right>
      <UDashboardSearchButton label="Rechercher…" class="w-40 sm:w-64" />
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

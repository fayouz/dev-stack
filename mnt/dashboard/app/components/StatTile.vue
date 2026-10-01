<script setup lang="ts">
import type { RouteLocationRaw } from 'vue-router'

defineProps<{
  label: string
  value: string | number
  icon: string
  hint?: string
  to?: RouteLocationRaw
  // Statut : toujours accompagné de son icône, jamais la couleur seule
  status?: 'success' | 'warning' | 'error' | 'neutral'
}>()
</script>

<template>
  <ULink :to="to" class="block" :class="{ 'pointer-events-none': !to }">
    <UCard class="h-full transition-colors hover:bg-elevated/40" :ui="{ body: 'p-4 sm:p-4' }">
      <div class="flex items-start justify-between gap-2">
        <p class="text-sm text-muted">{{ label }}</p>
        <UIcon
          :name="icon"
          class="size-5 shrink-0"
          :class="{
            'text-success': status === 'success',
            'text-warning': status === 'warning',
            'text-error': status === 'error',
            'text-muted': !status || status === 'neutral',
          }"
        />
      </div>
      <p class="mt-1 text-2xl font-semibold text-highlighted">{{ value }}</p>
      <p v-if="hint" class="mt-1 truncate text-xs text-muted">{{ hint }}</p>
    </UCard>
  </ULink>
</template>

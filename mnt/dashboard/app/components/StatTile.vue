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
    <UCard class="h-full transition-colors hover:bg-elevated/40" :ui="{ body: 'px-3 py-2 sm:px-3 sm:py-2' }">
      <div class="flex items-center justify-between gap-2">
        <p class="truncate text-xs text-muted">{{ label }}</p>
        <UIcon
          :name="icon"
          class="size-4 shrink-0"
          :class="{
            'text-success': status === 'success',
            'text-warning': status === 'warning',
            'text-error': status === 'error',
            'text-muted': !status || status === 'neutral',
          }"
        />
      </div>
      <p class="truncate text-xl/7 font-semibold text-highlighted">{{ value }}</p>
      <p v-if="hint" class="truncate text-xs text-muted" :title="hint">{{ hint }}</p>
    </UCard>
  </ULink>
</template>

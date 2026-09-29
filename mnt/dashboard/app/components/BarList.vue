<script setup lang="ts">
// Barres horizontales d'une seule teinte : magnitude, valeur au bout de la barre
const props = defineProps<{
  items: Array<{ label: string, value: number, display: string }>
}>()

const max = computed(() => Math.max(...props.items.map(i => i.value), 0) || 1)
</script>

<template>
  <ul class="flex flex-col gap-2.5">
    <li v-for="item in items" :key="item.label" class="grid grid-cols-[8rem_1fr] items-center gap-3 text-sm">
      <span class="truncate text-default" :title="item.label">{{ item.label }}</span>
      <UTooltip :text="`${item.label} : ${item.display}`">
        <div class="flex items-center gap-2 py-1" tabindex="0">
          <div
            class="h-2.5 min-w-1 rounded-e-[4px] transition-[width] duration-700 ease-out hover:brightness-110"
            :style="{ width: `${Math.max(1, 100 * item.value / max) * 0.8}%`, background: 'var(--viz-1)' }"
          />
          <span class="shrink-0 text-xs text-muted tabular-nums">{{ item.display }}</span>
        </div>
      </UTooltip>
    </li>
    <li v-if="!items.length" class="text-sm text-muted">Aucune donnée</li>
  </ul>
</template>

<script setup lang="ts">
// Mini-courbe de tendance (une seule série, sans axe) : la forme compte, pas l'échelle.
// Échelle automatique avec une amplitude minimale de 10 points pour distinguer stable / en hausse.
const props = defineProps<{
  values: number[]
  label: string
}>()

const shape = computed(() => {
  const values = props.values
  if (values.length < 2) return null
  const min = Math.min(...values)
  const max = Math.max(...values)
  const pad = Math.max(0, 10 - (max - min)) / 2
  const low = min - pad
  const span = (max + pad) - low || 1
  const coords = values.map((v, i) => [i / (values.length - 1) * 100, 22 - (v - low) / span * 20] as const)
  const points = coords.map(([x, y]) => `${x.toFixed(1)},${y.toFixed(1)}`).join(' ')
  // Compare le début et la fin de la fenêtre (moyennes sur un cinquième des points)
  const n = Math.max(1, Math.floor(values.length / 5))
  const avg = (list: number[]) => list.reduce((s, v) => s + v, 0) / list.length
  const delta = avg(values.slice(-n)) - avg(values.slice(0, n))
  const direction = delta > 5
    ? { text: 'en hausse', icon: 'i-lucide-trending-up' }
    : delta < -5
      ? { text: 'en baisse', icon: 'i-lucide-trending-down' }
      : { text: 'stable', icon: 'i-lucide-move-right' }
  return { points, min, max, ...direction }
})
</script>

<template>
  <div
    v-if="shape"
    class="flex items-center gap-1.5"
    role="img"
    :aria-label="`${label}, 15 dernières minutes : ${shape.text}, de ${formatPercent(shape.min)} à ${formatPercent(shape.max)}`"
    :title="`15 min : ${shape.text} (${formatPercent(shape.min)} – ${formatPercent(shape.max)})`"
  >
    <svg viewBox="0 0 100 24" preserveAspectRatio="none" class="h-5 w-20 overflow-visible" aria-hidden="true">
      <polyline :points="shape.points" fill="none" stroke="var(--viz-1)" stroke-width="1.5" vector-effect="non-scaling-stroke" stroke-linejoin="round" stroke-linecap="round" />
    </svg>
    <UIcon :name="shape.icon" class="size-3.5 shrink-0 text-muted" aria-hidden="true" />
  </div>
</template>

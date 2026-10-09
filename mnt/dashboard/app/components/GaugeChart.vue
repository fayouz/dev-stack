<script setup lang="ts">
// Jauge en demi-cercle : la couleur du remplissage porte la sévérité,
// toujours doublée d'une icône et d'un libellé (jamais la couleur seule).
// Arc dessiné en SVG avec pathLength=100 : la longueur remplie vaut exactement le pourcentage
const props = defineProps<{
  label: string
  value: number | null | undefined
  detail?: string
  icon: string
  // Valeurs récentes (en %) pour la tendance sous la jauge
  trend?: number[]
}>()

const percent = computed(() => Math.min(100, Math.max(0, props.value ?? 0)))

// Seuils : < 60 % normal, 60–80 % élevé, > 80 % critique
const severity = computed(() => {
  if (percent.value > 80) return { color: 'var(--viz-critical)', track: 'var(--viz-critical-track)', icon: 'i-lucide-octagon-alert', text: 'Critique', class: 'text-error' }
  if (percent.value >= 60) return { color: 'var(--viz-warning)', track: 'var(--viz-warning-track)', icon: 'i-lucide-triangle-alert', text: 'Élevé', class: 'text-warning' }
  return { color: 'var(--viz-good)', track: 'var(--viz-good-track)', icon: null, text: null, class: '' }
})

// Demi-cercle de rayon 80 centré en (100, 95), parcouru de gauche à droite
const ARC = 'M 20 95 A 80 80 0 0 1 180 95'

// Tendance : échelle automatique (amplitude minimale 10 points) pour voir stable / en hausse
const sparkline = computed(() => {
  const values = props.trend ?? []
  if (values.length < 2) return null
  const min = Math.min(...values)
  const max = Math.max(...values)
  const pad = Math.max(0, 10 - (max - min)) / 2
  const low = min - pad
  const span = (max + pad) - low || 1
  const points = values.map((v, i) => `${(i / (values.length - 1) * 100).toFixed(1)},${(24 - (v - low) / span * 22).toFixed(1)}`).join(' ')
  // Compare le début et la fin de la fenêtre (moyennes sur un cinquième des points)
  const n = Math.max(1, Math.floor(values.length / 5))
  const avg = (list: number[]) => list.reduce((s, v) => s + v, 0) / list.length
  const delta = avg(values.slice(-n)) - avg(values.slice(0, n))
  const direction = delta > 5
    ? { text: 'en hausse', icon: 'i-lucide-trending-up' }
    : delta < -5
      ? { text: 'en baisse', icon: 'i-lucide-trending-down' }
      : { text: 'stable', icon: 'i-lucide-move-right' }
  return { points, ...direction }
})
</script>

<template>
  <UCard :ui="{ body: 'flex flex-col gap-1 p-4 sm:p-4' }">
    <div class="flex items-center gap-2 text-sm text-muted">
      <UIcon :name="icon" /> {{ label }}
    </div>

    <div class="relative">
      <svg viewBox="0 0 200 105" class="mx-auto block h-[130px] w-full max-w-64" role="img" :aria-label="`${label} : ${formatPercent(value)}`">
        <path :d="ARC" fill="none" :stroke="severity.track" stroke-width="16" pathLength="100" />
        <path
          v-if="percent > 0"
          :d="ARC"
          fill="none"
          :stroke="severity.color"
          stroke-width="16"
          pathLength="100"
          :stroke-dasharray="`${percent} 100`"
          class="transition-[stroke-dasharray] duration-500"
        />
      </svg>
      <p class="absolute inset-x-0 bottom-1 text-center text-2xl font-semibold text-highlighted">{{ formatPercent(value) }}</p>
    </div>

    <p v-if="severity.text" class="flex items-center justify-center gap-1 text-xs font-medium" :class="severity.class">
      <UIcon :name="severity.icon!" /> {{ severity.text }}
    </p>
    <div v-if="sparkline" class="flex items-center gap-2" :title="`Tendance : ${sparkline.text}`">
      <svg viewBox="0 0 100 26" preserveAspectRatio="none" class="h-6 flex-1" aria-hidden="true">
        <polyline :points="sparkline.points" fill="none" stroke="var(--viz-1)" stroke-width="1.5" vector-effect="non-scaling-stroke" stroke-linejoin="round" />
      </svg>
      <span class="flex shrink-0 items-center gap-1 text-xs text-muted">
        <UIcon :name="sparkline.icon" /> {{ sparkline.text }}
      </span>
    </div>
    <p v-if="detail" class="text-center text-xs text-muted">{{ detail }}</p>
  </UCard>
</template>

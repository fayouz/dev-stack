<script setup lang="ts">
// Jauge en demi-cercle : la couleur du remplissage porte la sévérité,
// toujours doublée d'une icône et d'un libellé (jamais la couleur seule)
const props = defineProps<{
  label: string
  value: number | null | undefined
  detail?: string
  icon: string
}>()

const percent = computed(() => Math.min(100, Math.max(0, props.value ?? 0)))

const severity = computed(() => {
  if (percent.value >= 90) return { color: 'var(--viz-critical)', track: 'var(--viz-critical-track)', icon: 'i-lucide-octagon-alert', text: 'Critique', class: 'text-error' }
  if (percent.value >= 75) return { color: 'var(--viz-warning)', track: 'var(--viz-warning-track)', icon: 'i-lucide-triangle-alert', text: 'Élevé', class: 'text-warning' }
  return { color: 'var(--viz-1)', track: 'var(--viz-1-track)', icon: null, text: null, class: '' }
})

// Piste : pas plus clair de la même teinte que le remplissage
const categories = computed(() => ({
  used: { name: props.label, color: severity.value.color },
  free: { name: 'Libre', color: severity.value.track },
}))
</script>

<template>
  <UCard :ui="{ body: 'flex flex-col gap-1 p-4 sm:p-4' }">
    <div class="flex items-center gap-2 text-sm text-muted">
      <UIcon :name="icon" /> {{ label }}
    </div>

    <div class="relative">
      <DonutChart
        :data="[percent, 100 - percent]"
        :categories="categories"
        :type="DonutType.Half"
        :radius="4"
        :arc-width="14"
        :height="150"
        hide-legend
        hide-tooltip
        :aria-label="`${label} : ${formatPercent(value)}`"
      />
      <p class="absolute inset-x-0 bottom-3 text-center text-2xl font-semibold text-highlighted">{{ formatPercent(value) }}</p>
    </div>

    <p v-if="severity.text" class="flex items-center justify-center gap-1 text-xs font-medium" :class="severity.class">
      <UIcon :name="severity.icon!" /> {{ severity.text }}
    </p>
    <p v-if="detail" class="text-center text-xs text-muted">{{ detail }}</p>
  </UCard>
</template>

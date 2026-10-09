<script setup lang="ts">
// Jauge en demi-cercle. Arc SVG avec pathLength=100 : la longueur remplie vaut
// exactement le pourcentage. La couleur porte la sévérité, doublée d'un libellé.
const props = defineProps<{
  label: string
  value: number | null
  color: string
}>()

const percent = computed(() => Math.min(100, Math.max(0, props.value ?? 0)))

// Demi-cercle de rayon 80 centré en (100, 95), parcouru de gauche à droite
const ARC = 'M 20 95 A 80 80 0 0 1 180 95'
</script>

<template>
  <div class="relative">
    <svg viewBox="0 0 200 105" class="mx-auto block w-full max-w-40" role="img" :aria-label="`${label} : ${formatPercent(value)}`">
      <path :d="ARC" fill="none" stroke="var(--ui-bg-accented)" stroke-width="18" pathLength="100" />
      <path
        v-if="percent > 0"
        :d="ARC"
        fill="none"
        :stroke="color"
        stroke-width="18"
        pathLength="100"
        :stroke-dasharray="`${percent} 100`"
        class="transition-[stroke-dasharray] duration-500"
      />
    </svg>
    <p class="absolute inset-x-0 bottom-0 text-center text-lg font-semibold text-highlighted tabular-nums">
      {{ formatPercent(value) }}
    </p>
  </div>
</template>

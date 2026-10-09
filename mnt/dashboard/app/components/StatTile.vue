<script setup lang="ts">
import type { RouteLocationRaw } from 'vue-router'

// Carte indicateur standard : libellé, valeur, ligne de contexte, icône de statut.
// Avec `pressed` défini, la carte entière est un bouton bascule (filtre de la liste) ;
// le lien secondaire reste un vrai lien, posé au-dessus du bouton (pas de lien dans un bouton).
const props = defineProps<{
  label: string
  value: string | number
  // Total affiché en plus discret après la valeur (« 12 / 14 »)
  total?: number
  icon: string
  hint?: string
  // Statut : toujours accompagné de son icône et de la ligne de contexte, jamais la couleur seule
  status?: 'success' | 'warning' | 'error' | 'neutral'
  pressed?: boolean
  link?: { to: RouteLocationRaw, label: string }
}>()

const emit = defineEmits<{ toggle: [] }>()

const hintId = useId()
const isToggle = computed(() => props.pressed !== undefined)

const TONES = {
  success: 'bg-success/10 text-success',
  warning: 'bg-warning/10 text-warning',
  error: 'bg-error/10 text-error',
  neutral: 'bg-elevated text-muted',
}
const tone = computed(() => TONES[props.status ?? 'neutral'])

const ariaLabel = computed(() => {
  const value = props.total != null ? `${props.value} sur ${props.total}` : props.value
  return `${props.label} : ${value}. ${props.pressed ? 'Filtre actif, activer pour le retirer' : 'Filtrer la liste des conteneurs'}`
})
</script>

<template>
  <div
    class="relative flex h-full min-w-0 flex-col gap-1 rounded-lg bg-default p-3 ring transition-[background-color,box-shadow]"
    :class="pressed ? 'bg-primary/5 ring-2 ring-primary' : 'ring-default hover:ring-accented'"
  >
    <!-- Bouton étiré sur toute la carte : grande cible, focus visible sur le contour -->
    <button
      v-if="isToggle"
      type="button"
      class="absolute inset-0 cursor-pointer rounded-lg focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
      :aria-pressed="pressed"
      :aria-label="ariaLabel"
      :aria-describedby="hint ? hintId : undefined"
      @click="emit('toggle')"
    />

    <div class="pointer-events-none relative flex items-start justify-between gap-2">
      <p class="flex min-w-0 items-center gap-1.5 text-xs font-medium text-muted">
        <span class="truncate">{{ label }}</span>
        <span v-if="pressed" class="inline-flex shrink-0 items-center gap-0.5 text-primary">
          <UIcon name="i-lucide-list-filter" class="size-3.5" /> Filtre
        </span>
      </p>
      <span class="flex size-7 shrink-0 items-center justify-center rounded-md" :class="tone">
        <UIcon :name="icon" class="size-4" />
      </span>
    </div>

    <p class="pointer-events-none relative truncate text-2xl/8 font-semibold text-highlighted tabular-nums">
      {{ value }}<span v-if="total != null" class="text-base font-normal text-muted"> / {{ total }}</span>
    </p>

    <div class="relative mt-auto flex items-center justify-between gap-2 text-xs">
      <p v-if="hint" :id="hintId" class="pointer-events-none truncate text-muted" :title="hint">{{ hint }}</p>
      <ULink
        v-if="link"
        :to="link.to"
        class="relative ms-auto inline-flex shrink-0 items-center rounded p-0.5 text-muted hover:bg-elevated hover:text-highlighted focus-visible:outline-2 focus-visible:outline-primary"
        :aria-label="link.label"
        :title="link.label"
      >
        <UIcon name="i-lucide-arrow-up-right" class="size-4" />
      </ULink>
    </div>
  </div>
</template>

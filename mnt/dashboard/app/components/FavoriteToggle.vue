<script setup lang="ts">
// Étoile « favori » d'un conteneur : pleine et toujours visible quand elle est active,
// discrète sinon (révélée au survol ou au focus de la ligne)
const props = defineProps<{ name: string }>()
const { isFavorite, toggle } = useFavorites()
const active = computed(() => isFavorite(props.name))
</script>

<template>
  <UButton
    icon="i-lucide-star"
    color="neutral"
    variant="ghost"
    size="xs"
    square
    :aria-pressed="active"
    :aria-label="active ? `Retirer ${name} des favoris` : `Ajouter ${name} aux favoris`"
    :title="active ? 'Retirer des favoris' : 'Ajouter aux favoris'"
    :class="active ? 'text-warning hover:text-warning' : ['text-dimmed hover:text-warning', REVEAL_CLASS]"
    @click="toggle(name)"
  />
</template>

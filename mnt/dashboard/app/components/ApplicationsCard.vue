<script setup lang="ts">
// Conservé pour compatibilité : la liste des conteneurs, filtrée par défaut sur les applications
const filter = ref<ContainerFilter | null>('app')
</script>

<template>
  <ContainerList :filter="filter" @clear-filter="filter = null" />
</template>

<script setup lang="ts">
useHead({ title: 'Sauvegardes' })
</script>

<template>
  <UDashboardPanel id="backups">
    <template #header>
      <PageNavbar title="Sauvegardes" />
    </template>
    <template #body>
      <BackupsCard />
    </template>
  </UDashboardPanel>
</template>

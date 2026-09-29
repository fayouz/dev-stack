<script setup lang="ts">
useHead({ title: 'Mises à jour' })
</script>

<template>
  <UDashboardPanel id="updates">
    <template #header>
      <PageNavbar title="Mises à jour" />
    </template>
    <template #body>
      <UpdatesCard />
    </template>
  </UDashboardPanel>
</template>

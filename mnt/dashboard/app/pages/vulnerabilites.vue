<script setup lang="ts">
useHead({ title: 'Vulnérabilités' })
</script>

<template>
  <UDashboardPanel id="vulnerabilities">
    <template #header>
      <PageNavbar title="Vulnérabilités" />
    </template>
    <template #body>
      <VulnerabilitiesCard />
    </template>
  </UDashboardPanel>
</template>

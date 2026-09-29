<script setup lang="ts">
useHead({ title: 'Services' })
</script>

<template>
  <UDashboardPanel id="services">
    <template #header>
      <PageNavbar title="Services" />
    </template>
    <template #body>
      <ServicesTable />
    </template>
  </UDashboardPanel>
</template>

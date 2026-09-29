<script setup lang="ts">
useHead({
  titleTemplate: title => (title ? `${title} · Docker Master` : 'Docker Master'),
})
</script>

<template>
  <UApp>
    <NuxtLayout>
      <NuxtPage />
    </NuxtLayout>
  </UApp>
</template>

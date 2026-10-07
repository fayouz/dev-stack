<script setup lang="ts">
// Bandeau affiché quand Docker, trop chargé, n'a pas répondu à temps :
// la liste affichée est la dernière obtenue
const { data } = await useContainers()
const now = ref(Date.now())
let timer: ReturnType<typeof setInterval> | undefined
onMounted(() => { timer = setInterval(() => { now.value = Date.now() }, 5_000) })
onBeforeUnmount(() => clearInterval(timer))

const age = computed(() => data.value?.listedAt ? Math.round((now.value - data.value.listedAt) / 1000) : 0)
</script>

<template>
  <UAlert
    v-if="age > 30"
    icon="i-lucide-hourglass"
    color="warning"
    variant="subtle"
    :title="`Docker répond lentement : état des services d'il y a ${age} s`"
    description="La machine est très chargée. L'affichage se mettra à jour dès que Docker répondra."
    class="shrink-0"
  />
</template>

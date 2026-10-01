<script setup lang="ts">
// Demi-donut de la répartition des états des services, légende icône + libellé + nombre
const props = withDefaults(defineProps<{
  title?: string
  segments: Array<{ key: string, label: string, count: number, color: string, icon: string }>
}>(), { title: 'État des services' })

const total = computed(() => props.segments.reduce((sum, s) => sum + s.count, 0))
const categories = computed(() => Object.fromEntries(props.segments.map(s => [s.key, { name: s.label, color: s.color }])))
</script>

<template>
  <UCard :ui="{ body: 'flex flex-col gap-1 p-4 sm:p-4' }">
    <div class="flex items-center gap-2 text-sm text-muted">
      <UIcon name="i-lucide-boxes" /> {{ title }}
    </div>

    <div class="relative">
      <DonutChart
        :data="segments.map(s => s.count)"
        :categories="categories"
        :type="DonutType.Half"
        :radius="2"
        :arc-width="14"
        :pad-angle="0.02"
        :height="150"
        hide-legend
      />
      <div class="pointer-events-none absolute inset-x-0 bottom-2 text-center">
        <p class="text-2xl font-semibold text-highlighted">{{ total }}</p>
        <p class="text-xs text-muted">services</p>
      </div>
    </div>

    <ul class="flex flex-wrap justify-center gap-x-3 gap-y-1 text-xs">
      <li v-for="segment in segments" :key="segment.key" class="flex items-center gap-1" :class="segment.count ? 'text-default' : 'text-dimmed'">
        <span class="size-2.5 rounded-sm" :style="{ background: segment.color }" />
        <UIcon :name="segment.icon" class="text-muted" />
        {{ segment.label }} <span class="font-semibold tabular-nums">{{ segment.count }}</span>
      </li>
    </ul>
  </UCard>
</template>

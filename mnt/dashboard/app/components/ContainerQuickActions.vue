<script setup lang="ts">
// Actions rapides d'une ligne de conteneur : démarrer, ou redémarrer / arrêter,
// puis logs (et activité en option). Confirmation via useContainerActions + ContainerActionModal.
const props = defineProps<{
  container: { name: string, state: string, stopProtected: boolean }
  actions: ContainerActions
  activity?: boolean
}>()
const emit = defineEmits<{ open: [tab: 'activity' | 'logs'] }>()

const { pending, running } = props.actions
const busy = computed(() => running.value[props.container.name])
const ask = (action: ContainerAction) => { pending.value = { name: props.container.name, action } }
</script>

<template>
  <div class="flex shrink-0 items-center justify-end gap-0.5">
    <template v-if="container.state === 'running'">
      <UButton
        icon="i-lucide-rotate-cw"
        color="neutral"
        variant="ghost"
        size="xs"
        square
        :class="REVEAL_CLASS"
        :loading="busy === 'restart'"
        :disabled="!!busy"
        :aria-label="`Redémarrer ${container.name}`"
        title="Redémarrer"
        @click="ask('restart')"
      />
      <UButton
        v-if="!container.stopProtected"
        icon="i-lucide-square"
        color="error"
        variant="ghost"
        size="xs"
        square
        :class="REVEAL_CLASS"
        :loading="busy === 'stop'"
        :disabled="!!busy"
        :aria-label="`Arrêter ${container.name}`"
        title="Arrêter"
        @click="ask('stop')"
      />
      <!-- Conteneur protégé : emplacement conservé pour garder les colonnes alignées -->
      <span v-else class="inline-flex size-6 items-center justify-center text-dimmed" title="Arrêt désactivé pour ce service">
        <UIcon name="i-lucide-lock" class="size-3" />
        <span class="sr-only">Arrêt désactivé pour {{ container.name }}</span>
      </span>
    </template>
    <template v-else>
      <UButton
        icon="i-lucide-play"
        color="success"
        variant="ghost"
        size="xs"
        square
        :class="REVEAL_CLASS"
        :loading="busy === 'start'"
        :disabled="!!busy"
        :aria-label="`Démarrer ${container.name}`"
        title="Démarrer"
        @click="ask('start')"
      />
      <span class="size-6" aria-hidden="true" />
    </template>
    <UButton
      v-if="activity"
      icon="i-lucide-chart-line"
      color="neutral"
      variant="ghost"
      size="xs"
      square
      :class="REVEAL_CLASS"
      :aria-label="`Activité de ${container.name}`"
      title="Activité"
      @click="emit('open', 'activity')"
    />
    <UButton
      icon="i-lucide-scroll-text"
      color="neutral"
      variant="ghost"
      size="xs"
      square
      :class="REVEAL_CLASS"
      :aria-label="`Logs de ${container.name}`"
      title="Logs"
      @click="emit('open', 'logs')"
    />
  </div>
</template>

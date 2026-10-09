<script setup lang="ts">
// Confirmation d'une action start / stop / restart (voir useContainerActions)
const props = defineProps<{ actions: ContainerActions }>()
const { pending, confirmOpen } = props.actions
</script>

<template>
  <UModal
    v-model:open="confirmOpen"
    :title="pending ? `${ACTION_LABELS[pending.action].verb} ${pending.name} ?` : ''"
    :description="pending?.action === 'restart' ? 'Le service sera indisponible pendant le redémarrage.' : undefined"
  >
    <template #footer>
      <div class="flex w-full justify-end gap-2">
        <UButton label="Annuler" color="neutral" variant="outline" @click="pending = null" />
        <UButton
          v-if="pending"
          :label="ACTION_LABELS[pending.action].verb"
          :color="pending.action === 'stop' ? 'error' : 'primary'"
          @click="actions.confirmAction"
        />
      </div>
    </template>
  </UModal>
</template>

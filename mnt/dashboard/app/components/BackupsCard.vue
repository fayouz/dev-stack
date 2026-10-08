<script setup lang="ts">
const { data } = await useBackups()

const lastRun = computed(() => data.value?.available ? data.value.lastRun : null)
const snapshots = computed(() => data.value?.available ? data.value.snapshots.slice(0, 8) : [])

const toast = useToast()
const busy = computed(() => !!(data.value?.requested || data.value?.running))
usePollWhile(busy, 'backups')

// Fin d'une sauvegarde suivie depuis cette page : on prévient du résultat
watch(busy, (now, before) => {
  if (!before || now || !lastRun.value) return
  if (lastRun.value.result === 'ok') toast.add({ title: 'Sauvegarde terminée', color: 'success', icon: 'i-lucide-circle-check' })
  else if (lastRun.value.result === 'error') toast.add({ title: 'La sauvegarde a échoué', description: lastRun.value.message, color: 'error', icon: 'i-lucide-circle-x' })
})

async function backupNow() {
  const failure = await postAction('/api/backups/run')
  if (failure) toast.add({ title: 'Impossible de lancer la sauvegarde', description: failure, color: 'error', icon: 'i-lucide-circle-x' })
  await refreshNuxtData('backups')
}
</script>

<template>
  <UCard>
    <template #header>
      <div class="flex items-center justify-between gap-3">
        <div>
          <h2 class="flex items-center gap-2 font-semibold">
            <UIcon name="i-lucide-archive" /> Sauvegardes
          </h2>
          <p v-if="data?.running" class="text-sm text-muted">Sauvegarde en cours…</p>
          <p v-else-if="data?.requested" class="text-sm text-muted">Sauvegarde demandée, démarrage imminent…</p>
          <p v-else-if="lastRun && lastRun.result !== 'none'" class="text-sm text-muted">
            Dernière exécution {{ formatRelative(lastRun.at) }}
          </p>
        </div>
        <UButton
          label="Sauvegarder maintenant"
          icon="i-lucide-save"
          size="sm"
          :loading="busy"
          :disabled="busy"
          @click="backupNow"
        />
      </div>
    </template>

    <UAlert
      v-if="data && !data.available"
      icon="i-lucide-info"
      color="neutral"
      variant="subtle"
      title="Aucun état de sauvegarde"
      description="Le conteneur restic n'a pas encore écrit son état. Lancez une première sauvegarde."
    />
    <template v-else-if="lastRun">
      <UAlert
        v-if="lastRun.result === 'error'"
        icon="i-lucide-circle-x"
        color="error"
        variant="subtle"
        title="La dernière sauvegarde a échoué"
        :description="`${lastRun.message} — voir docker logs restic`"
        class="mb-4"
      />
      <UAlert
        v-else-if="lastRun.result === 'ok'"
        icon="i-lucide-circle-check"
        color="success"
        variant="subtle"
        :title="`Sauvegarde réussie le ${formatDate(lastRun.at)}`"
        class="mb-4"
      />

      <ul class="divide-y divide-default">
        <li v-for="snapshot in snapshots" :key="snapshot.id" class="flex items-center justify-between gap-3 py-2 text-sm">
          <div class="flex min-w-0 items-center gap-2">
            <span class="font-mono text-xs text-muted">{{ snapshot.id }}</span>
            <UBadge v-for="tag in snapshot.tags" :key="tag" color="neutral" variant="subtle" size="sm">{{ tag }}</UBadge>
          </div>
          <div class="flex shrink-0 gap-3 text-muted">
            <span class="tabular-nums">{{ formatBytes(snapshot.size) }}</span>
            <span>{{ formatDate(snapshot.time) }}</span>
          </div>
        </li>
      </ul>
    </template>
  </UCard>
</template>

<script setup lang="ts">
const { data, error } = await useUpdates()
const config = useRuntimeConfig()

function diffColor(diff: string | null) {
  if (diff === 'major') return 'error' as const
  if (diff === 'minor') return 'warning' as const
  if (diff === 'patch') return 'success' as const
  return 'neutral' as const
}
</script>

<template>
  <UCard>
    <template #header>
      <div class="flex items-center justify-between gap-3">
        <div>
          <h2 class="flex items-center gap-2 font-semibold">
            <UIcon name="i-lucide-package" /> Mises à jour
          </h2>
          <p v-if="data" class="text-sm text-muted">
            {{ data.updates.length }} disponible(s) sur {{ data.watched }} conteneurs surveillés
          </p>
        </div>
        <UButton
          v-if="config.public.wudPublicUrl"
          :to="config.public.wudPublicUrl"
          target="_blank"
          label="Mettre à jour dans WUD"
          trailing-icon="i-lucide-external-link"
          size="sm"
        />
      </div>
    </template>

    <UAlert
      v-if="error"
      icon="i-lucide-triangle-alert"
      color="error"
      variant="subtle"
      title="WUD injoignable"
      :description="error.statusMessage"
    />
    <p v-else-if="data && !data.updates.length" class="text-sm text-muted">
      Toutes les images sont à jour.
    </p>
    <ul v-else-if="data" class="divide-y divide-default">
      <li v-for="update in data.updates" :key="update.name" class="flex items-center justify-between gap-3 py-2">
        <div class="min-w-0">
          <p class="font-medium">{{ update.name }}</p>
          <p class="truncate font-mono text-xs text-muted">{{ update.image }}</p>
        </div>
        <div class="flex shrink-0 items-center gap-2 text-sm">
          <span class="font-mono text-muted">{{ update.current }}</span>
          <UIcon name="i-lucide-arrow-right" class="text-muted" />
          <span class="font-mono">{{ update.next }}</span>
          <UBadge v-if="update.semverDiff" :color="diffColor(update.semverDiff)" variant="subtle" size="sm">
            {{ update.semverDiff }}
          </UBadge>
        </div>
      </li>
    </ul>
    <p v-if="data?.errors" class="mt-3 text-xs text-warning">
      {{ data.errors }} conteneur(s) n'ont pas pu être vérifiés (limite Docker Hub ?).
    </p>
  </UCard>
</template>

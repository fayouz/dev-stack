<script setup lang="ts">
const { data, error } = await useUpdates()
const config = useRuntimeConfig()

type Update = NonNullable<typeof data.value>['updates'][number]
const toast = useToast()

// Ces services portent l'accès au dashboard : la page sera coupée un instant
const DISRUPTIVE = ['traefik', 'dashboard', 'tinyauth', 'docker-socket-proxy', 'docker-socket-proxy-actions']

const pending = ref<Update | null>(null)
const confirmOpen = computed({
  get: () => pending.value !== null,
  set: (open) => { if (!open) pending.value = null },
})
const updating = ref<Record<string, boolean>>({})

async function confirmUpdate() {
  const update = pending.value
  if (!update) return
  pending.value = null
  updating.value[update.id] = true
  toast.add({ title: `Mise à jour de ${update.name} lancée`, description: 'Téléchargement de l\'image puis recréation du conteneur.', icon: 'i-lucide-loader' })
  const failure = await postAction(`/api/updates/${encodeURIComponent(update.id)}`)
  if (failure) {
    toast.add({ title: `Échec de la mise à jour de ${update.name}`, description: failure, color: 'error', icon: 'i-lucide-circle-x' })
  } else {
    toast.add({ title: `${update.name} mis à jour en ${update.next}`, color: 'success', icon: 'i-lucide-circle-check' })
  }
  delete updating.value[update.id]
  await refreshNuxtData(['updates', 'containers'])
}

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
          label="Ouvrir WUD"
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
          <UButton
            label="Mettre à jour"
            icon="i-lucide-download"
            size="xs"
            variant="soft"
            :color="update.semverDiff === 'major' ? 'warning' : 'primary'"
            :loading="updating[update.id]"
            :disabled="updating[update.id]"
            @click="pending = update"
          />
        </div>
      </li>
    </ul>
    <p v-if="data?.errors" class="mt-3 text-xs text-warning">
      {{ data.errors }} conteneur(s) n'ont pas pu être vérifiés (limite Docker Hub ?).
    </p>

    <UModal
      v-model:open="confirmOpen"
      :title="pending ? `Mettre à jour ${pending.name} ?` : ''"
      :description="pending ? `${pending.current} → ${pending.next}. WUD réécrit le tag dans le compose (copie .back), télécharge l'image et recrée le conteneur.` : undefined"
    >
      <template v-if="pending && (pending.semverDiff === 'major' || DISRUPTIVE.includes(pending.name))" #body>
        <UAlert
          v-if="pending.semverDiff === 'major'"
          icon="i-lucide-triangle-alert"
          color="warning"
          variant="subtle"
          title="Version majeure"
          description="Peut casser la compatibilité (données, configuration). Faire une sauvegarde avant."
        />
        <UAlert
          v-if="DISRUPTIVE.includes(pending.name)"
          icon="i-lucide-unplug"
          color="neutral"
          variant="subtle"
          title="Le dashboard sera coupé quelques secondes"
          description="Recharger la page une fois le conteneur redémarré."
          :class="{ 'mt-3': pending.semverDiff === 'major' }"
        />
      </template>
      <template #footer>
        <div class="flex w-full justify-end gap-2">
          <UButton label="Annuler" color="neutral" variant="outline" @click="pending = null" />
          <UButton label="Mettre à jour" :color="pending?.semverDiff === 'major' ? 'warning' : 'primary'" @click="confirmUpdate" />
        </div>
      </template>
    </UModal>
  </UCard>
</template>

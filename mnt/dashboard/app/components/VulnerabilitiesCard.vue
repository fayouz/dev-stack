<script setup lang="ts">
const { data } = await useVulnerabilities()
const toast = useToast()

const SEVERITIES = [
  { key: 'CRITICAL', label: 'Critiques', color: 'error' },
  { key: 'HIGH', label: 'Élevées', color: 'warning' },
  { key: 'MEDIUM', label: 'Moyennes', color: 'info' },
  { key: 'LOW', label: 'Faibles', color: 'neutral' },
] as const

const images = computed(() => data.value?.available ? data.value.images : [])
const totals = computed(() => Object.fromEntries(SEVERITIES.map(s => [
  s.key,
  images.value.reduce((sum, image) => sum + image.counts[s.key], 0),
])) as Record<typeof SEVERITIES[number]['key'], number>)
const failed = computed(() => images.value.filter(i => i.error).length)

const busy = computed(() => !!(data.value?.requested || data.value?.running))
usePollWhile(busy, 'vulnerabilities')

async function scanNow() {
  const failure = await postAction('/api/vulnerabilities/scan')
  if (failure) toast.add({ title: 'Impossible de lancer l\'analyse', description: failure, color: 'error', icon: 'i-lucide-circle-x' })
  await refreshNuxtData('vulnerabilities')
}

// Une image dépliée à la fois, pour voir le détail de ses failles critiques et élevées
const expanded = ref<string | null>(null)
const toggle = (image: string) => { expanded.value = expanded.value === image ? null : image }
</script>

<template>
  <UCard :ui="{ body: 'p-0 sm:p-0' }">
    <template #header>
      <div class="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 class="flex items-center gap-2 font-semibold">
            <UIcon name="i-lucide-shield-alert" /> Vulnérabilités
          </h2>
          <p class="text-sm text-muted">
            <template v-if="data?.running">Analyse en cours (plusieurs minutes)…</template>
            <template v-else-if="data?.requested">Analyse demandée, démarrage imminent…</template>
            <template v-else-if="data?.available">
              {{ images.length }} images analysées {{ formatRelative(data.scannedAt) }} par Trivy
            </template>
            <template v-else>Images des conteneurs en cours d'exécution, analysées par Trivy</template>
          </p>
        </div>
        <UButton
          label="Analyser maintenant"
          icon="i-lucide-scan-search"
          size="sm"
          :loading="busy"
          :disabled="busy"
          @click="scanNow"
        />
      </div>
      <div v-if="data?.available" class="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-4">
        <div v-for="s in SEVERITIES" :key="s.key" class="rounded-md border border-default px-3 py-2">
          <p class="text-xs text-muted">{{ s.label }}</p>
          <p class="text-xl font-semibold tabular-nums" :class="totals[s.key] && s.key === 'CRITICAL' ? 'text-error' : 'text-highlighted'">
            {{ totals[s.key] }}
          </p>
        </div>
      </div>
    </template>

    <UAlert
      v-if="data && !data.available"
      icon="i-lucide-info"
      color="neutral"
      variant="subtle"
      title="Aucune analyse pour l'instant"
      description="La première analyse se lance au démarrage du conteneur trivy (téléchargement de la base, puis quelques minutes par image)."
      class="m-4"
    />
    <p v-if="failed" class="mx-4 mt-4 text-xs text-warning">
      {{ failed }} image(s) n'ont pas pu être analysées : voir docker logs trivy.
    </p>

    <ul class="divide-y divide-default">
      <li v-for="image in images" :key="image.image">
        <button
          type="button"
          class="flex w-full items-center justify-between gap-3 px-4 py-2.5 text-left hover:bg-elevated/50"
          :aria-expanded="expanded === image.image"
          @click="toggle(image.image)"
        >
          <div class="min-w-0">
            <p class="truncate font-mono text-sm">{{ image.image }}</p>
            <p class="truncate text-xs text-muted">{{ image.containers.join(', ') }}</p>
          </div>
          <div class="flex shrink-0 items-center gap-1.5">
            <UBadge v-if="image.error" color="warning" variant="subtle" size="sm">non analysée</UBadge>
            <template v-else>
              <template v-for="s in SEVERITIES" :key="s.key">
                <UBadge v-if="image.counts[s.key]" :color="s.color" variant="subtle" size="sm" class="tabular-nums">
                  {{ image.counts[s.key] }} {{ s.label.toLowerCase() }}
                </UBadge>
              </template>
              <UBadge v-if="!SEVERITIES.some(s => image.counts[s.key])" color="success" variant="subtle" size="sm">
                aucune
              </UBadge>
            </template>
            <UIcon
              :name="expanded === image.image ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
              class="ml-1 text-muted"
            />
          </div>
        </button>

        <div v-if="expanded === image.image" class="bg-muted/40 px-4 py-3 text-sm">
          <p v-if="image.error" class="font-mono text-xs text-warning">{{ image.error }}</p>
          <template v-else>
            <p class="mb-2 text-xs text-muted">
              {{ image.fixable }} faille(s) corrigée(s) dans une version plus récente d'un paquet.
              Mettre l'image à jour corrige en général celles de l'image de base.
            </p>
            <p v-if="!image.top.length" class="text-muted">Aucune faille critique ou élevée.</p>
            <ul v-else class="space-y-1.5">
              <li v-for="v in image.top" :key="`${v.id}-${v.pkg}`" class="flex flex-wrap items-baseline gap-x-2">
                <UBadge :color="v.severity === 'CRITICAL' ? 'error' : 'warning'" variant="subtle" size="sm">
                  {{ v.severity === 'CRITICAL' ? 'critique' : 'élevée' }}
                </UBadge>
                <a
                  :href="`https://avd.aquasec.com/nvd/${v.id.toLowerCase()}`"
                  target="_blank"
                  rel="noopener"
                  class="font-mono text-xs text-primary hover:underline"
                >{{ v.id }}</a>
                <span class="font-mono text-xs">{{ v.pkg }} {{ v.installed }}</span>
                <span v-if="v.fixed" class="text-xs text-success">→ {{ v.fixed }}</span>
                <span class="min-w-0 basis-full truncate text-xs text-muted">{{ v.title }}</span>
              </li>
            </ul>
            <p v-if="image.counts.CRITICAL + image.counts.HIGH > image.top.length" class="mt-2 text-xs text-muted">
              … et {{ image.counts.CRITICAL + image.counts.HIGH - image.top.length }} autre(s).
            </p>
          </template>
        </div>
      </li>
    </ul>
  </UCard>
</template>

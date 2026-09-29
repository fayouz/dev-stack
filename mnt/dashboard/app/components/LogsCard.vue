<script setup lang="ts">
// Logs en temps réel d'un service, choisi dans le header de la carte
interface LogLine {
  id: number
  t: string
  s: 'out' | 'err'
  m: string
}

const MAX_LINES = 1000

const config = useRuntimeConfig()
const { data: containers } = await useContainers()

const services = computed(() => (containers.value?.containers ?? [])
  .filter(c => c.state === 'running')
  .map(c => ({ label: c.name, value: c.name, suffix: c.project ?? undefined })))

const selected = ref<string>(
  (containers.value?.containers ?? []).find(c => c.project === config.public.defaultProject && c.state === 'running')?.name ?? '',
)
const filter = ref('')
const following = ref(true)
const status = ref<'connecting' | 'live' | 'closed'>('closed')
const lines = ref<LogLine[]>([])
const viewport = ref<HTMLElement>()

let source: EventSource | undefined
let nextId = 0

function connect(name: string) {
  source?.close()
  lines.value = []
  if (!name) return
  status.value = 'connecting'
  source = new EventSource(`/api/logs/${encodeURIComponent(name)}`)
  source.onopen = () => { status.value = 'live' }
  source.onmessage = (message) => {
    const line = JSON.parse(message.data) as Omit<LogLine, 'id'>
    lines.value.push({ ...line, id: nextId++ })
    if (lines.value.length > MAX_LINES) lines.value.splice(0, lines.value.length - MAX_LINES)
  }
  // Fin de flux (conteneur arrêté) : on ne se reconnecte pas en boucle
  source.onerror = () => {
    status.value = 'closed'
    source?.close()
  }
}

watch(selected, connect)
onMounted(() => connect(selected.value))
onBeforeUnmount(() => source?.close())

const visible = computed(() => {
  const needle = filter.value.trim().toLowerCase()
  return needle ? lines.value.filter(l => l.m.toLowerCase().includes(needle)) : lines.value
})

// Suit la fin du flux tant que l'utilisateur ne remonte pas dans l'historique
watch(() => visible.value.length, async () => {
  if (!following.value) return
  await nextTick()
  viewport.value?.scrollTo({ top: viewport.value.scrollHeight })
})
function onScroll() {
  const el = viewport.value
  if (el) following.value = el.scrollHeight - el.scrollTop - el.clientHeight < 40
}
function resume() {
  following.value = true
  viewport.value?.scrollTo({ top: viewport.value.scrollHeight })
}

const time = (iso: string) => iso ? new Date(iso).toLocaleTimeString('fr-FR') : ''

// Beaucoup de services écrivent tout sur stderr : la couleur suit le niveau lu
// dans la ligne, stderr n'est signalé que par un trait dans la marge
const ERROR = /\b(error|err|fatal|panic|critical|exception)\b|level=(error|fatal)|ORA-\d+/i
const WARNING = /\b(warn|warning)\b|level=warn/i
function levelClass(message: string) {
  if (ERROR.test(message)) return 'text-error'
  if (WARNING.test(message)) return 'text-warning'
  return 'text-default'
}
</script>

<template>
  <UCard id="logs" class="shrink-0" :ui="{ body: 'p-0 sm:p-0' }">
    <template #header>
      <div class="flex flex-wrap items-center justify-between gap-3">
        <div class="flex items-center gap-2">
          <h3 class="font-semibold">Logs</h3>
          <UBadge
            :color="status === 'live' ? 'success' : status === 'connecting' ? 'warning' : 'neutral'"
            variant="subtle"
            size="sm"
          >
            <span v-if="status === 'live'" class="mr-1 inline-block size-1.5 animate-pulse rounded-full bg-success" />
            {{ status === 'live' ? 'en direct' : status === 'connecting' ? 'connexion…' : 'arrêté' }}
          </UBadge>
        </div>
        <div class="flex flex-wrap items-center gap-2">
          <UInput v-model="filter" icon="i-lucide-filter" placeholder="Filtrer les lignes…" size="sm" class="w-48" />
          <USelectMenu
            v-model="selected"
            :items="services"
            value-key="value"
            placeholder="Choisir un service"
            icon="i-lucide-container"
            size="sm"
            class="w-56"
          />
          <UButton
            icon="i-lucide-rotate-cw"
            color="neutral"
            variant="ghost"
            size="sm"
            aria-label="Reconnecter"
            @click="connect(selected)"
          />
          <UButton
            icon="i-lucide-eraser"
            color="neutral"
            variant="ghost"
            size="sm"
            aria-label="Effacer"
            @click="lines = []"
          />
        </div>
      </div>
    </template>

    <div class="relative">
      <div
        ref="viewport"
        class="h-96 overflow-auto bg-muted/40 px-4 py-2 font-mono text-xs leading-5"
        @scroll="onScroll"
      >
        <p v-if="!visible.length" class="py-8 text-center text-muted">
          {{ selected ? (filter ? 'Aucune ligne ne correspond au filtre.' : 'En attente de logs…') : 'Choisissez un service.' }}
        </p>
        <div
          v-for="line in visible"
          :key="line.id"
          class="flex gap-3 border-l-2 pl-2 whitespace-pre-wrap break-all"
          :class="[levelClass(line.m), line.s === 'err' ? 'border-(--ui-border-accented)' : 'border-transparent']"
          :title="line.s === 'err' ? 'stderr' : 'stdout'"
        >
          <span class="shrink-0 select-none text-dimmed">{{ time(line.t) }}</span>
          <span>{{ line.m }}</span>
        </div>
      </div>

      <UButton
        v-if="!following"
        icon="i-lucide-arrow-down"
        label="Reprendre le direct"
        size="xs"
        class="absolute bottom-3 left-1/2 -translate-x-1/2 shadow-md"
        @click="resume"
      />
    </div>
  </UCard>
</template>

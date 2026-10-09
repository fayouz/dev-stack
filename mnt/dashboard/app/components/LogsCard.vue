<script setup lang="ts">
// Logs en temps réel d'un service, choisi dans le header de la carte
// (ou imposé par `service`, depuis le tiroir de détail de la page Services)
const props = defineProps<{ service?: string }>()

interface LogLine {
  t: string
  s: 'out' | 'err'
  m: string
}

type Level = 'error' | 'warn' | 'info' | 'debug'

// Ligne affichée : les messages identiques consécutifs sont fusionnés (compteur ×N)
interface LogRow {
  id: number
  t: string
  s: 'out' | 'err'
  m: string
  // Métadonnées de tête (horodatage, pid, fichier:ligne), atténuées à l'affichage
  meta: string
  levelToken: string
  level: Level | null
  body: string
  key: string
  count: number
}

// Lignes affichées (après fusion) et lignes brutes conservées pour l'export
const MAX_LINES = 1000
const MAX_RAW = 5000

const config = useRuntimeConfig()
const { data: containers } = await useContainers()

const services = computed(() => (containers.value?.containers ?? [])
  .filter(c => c.state === 'running' || c.name === props.service)
  .map(c => ({ label: c.name, value: c.name, suffix: c.project ?? undefined })))

const selected = ref<string>(props.service
  ?? (containers.value?.containers ?? []).find(c => c.project === config.public.defaultProject && c.state === 'running')?.name
  ?? '')
const filter = ref('')
const following = ref(true)
const status = ref<'connecting' | 'live' | 'closed'>('closed')
const rows = ref<LogRow[]>([])
const raw = ref<LogLine[]>([])
const viewport = ref<HTMLElement>()

let source: EventSource | undefined
let nextId = 0

// --- Analyse d'une ligne : métadonnées de tête, niveau, message ---

// Préfixes retirés un à un en tête de message (dans n'importe quel ordre)
const META_PREFIXES = [
  // 2026-10-09T12:00:00.123Z, [2026-10-09 12:00:00,123 UTC], 2026/10/09 12:00:00
  /^\[?\d{4}[-/]\d{2}[-/]\d{2}[T ]\d{2}:\d{2}:\d{2}(?:[.,]\d+)?(?:Z|[+-]\d{2}:?\d{2}| [A-Z]{2,5})?\]?:?\s+/,
  // Syslog : Oct  9 12:00:00
  /^[A-Z][a-z]{2} +\d{1,2} \d{2}:\d{2}:\d{2}\s+/,
  // Heure seule : 12:00:00.123
  /^\[?\d{2}:\d{2}:\d{2}(?:[.,]\d+)?\]?\s+/,
  // logfmt : time=… ts=…
  /^(?:time|ts|timestamp)=(?:"[^"]*"|\S+)\s+/,
  // Processus : [1234], postgres[1234]:, 12#34: (nginx)
  /^\[\d+\]:?\s+/,
  /^[\w.-]+\[\d+\]:\s+/,
  /^\d+#\d+:\s+/,
  // Fichier source : main.go:123, src/app.py:45:
  /^[\w./-]+\.(?:go|py|js|ts|mjs|java|kt|rb|rs|php|c|cc|cpp|h):\d+:?\s+/,
]
// Niveau explicite en tête : level=info, [WARN], ERROR, info: (jamais un simple mot en minuscules : « Info about… »)
const LEVEL_PREFIXES = [/^level=(\w+)\s+/i, /^\[(\w+)\]:?\s+/, /^([A-Z]+):?\s+/, /^(\w+):\s+/]
const LEVELS: Record<string, Level> = {
  error: 'error', err: 'error', fatal: 'error', panic: 'error', critical: 'error', crit: 'error', emerg: 'error', alert: 'error',
  warn: 'warn', warning: 'warn',
  info: 'info', notice: 'info', log: 'info',
  debug: 'debug', trace: 'debug',
}

// Sans niveau explicite, on le devine dans le message (beaucoup de services écrivent tout sur stderr)
const ERROR = /\bE\d{4}\b|\b(error|err|fatal|panic|critical|exception)\b|level=(error|fatal)|ORA-\d+/i
const WARNING = /\b(warn|warning)\b|level=warn/i
const DEBUG = /\bdebug\b|level=(debug|trace)/i

function matchLevel(text: string) {
  for (const re of LEVEL_PREFIXES) {
    const match = text.match(re)
    if (match && Object.hasOwn(LEVELS, match[1]!.toLowerCase())) return match
  }
  return null
}

function parse(m: string) {
  let rest = m
  let meta = ''
  let levelToken = ''
  for (let i = 0; i < 8; i++) {
    const prefix = META_PREFIXES.map(re => rest.match(re)?.[0]).find(Boolean)
    if (prefix) {
      meta += prefix
      rest = rest.slice(prefix.length)
      continue
    }
    const level = !levelToken ? matchLevel(rest) : null
    if (level) {
      levelToken = level[1]!
      rest = rest.slice(level[0].length)
      continue
    }
    break
  }
  const level: Level | null = levelToken
    ? LEVELS[levelToken.toLowerCase()] ?? null
    : ERROR.test(rest) ? 'error' : WARNING.test(rest) ? 'warn' : DEBUG.test(rest) ? 'debug' : null
  // Clé de fusion : le message sans ses métadonnées (horodatages compris, où qu'ils soient)
  const key = `${levelToken.toLowerCase()}|${rest.replace(/\d{2}:\d{2}:\d{2}(?:[.,]\d+)?/g, '').trim() || m}`
  return { meta: meta.trimEnd(), levelToken, level, body: rest, key }
}

// --- Réception : pause locale ou globale, fusion, plafonds ---

function append(lines: LogLine[]) {
  raw.value.push(...lines)
  if (raw.value.length > MAX_RAW) raw.value.splice(0, raw.value.length - MAX_RAW)
  for (const line of lines) {
    const parsed = parse(line.m)
    const last = rows.value.at(-1)
    if (last && last.key === parsed.key && last.s === line.s) {
      last.count++
      last.t = line.t
      last.m = line.m
      last.meta = parsed.meta
    } else {
      rows.value.push({ id: nextId++, ...line, ...parsed, count: 1 })
    }
  }
  if (rows.value.length > MAX_LINES) rows.value.splice(0, rows.value.length - MAX_LINES)
}

// Pause globale (useRefreshPaused) ou locale à cette console : les lignes reçues
// sont mises de côté et affichées à la reprise
const globalPaused = useRefreshPaused()
const localPaused = ref(false)
const frozen = computed(() => globalPaused.value || localPaused.value)
const held = ref<LogLine[]>([])
watch(frozen, (value) => {
  if (value || !held.value.length) return
  append(held.value)
  held.value = []
})

function clear() {
  rows.value = []
  raw.value = []
  held.value = []
}

function connect(name: string) {
  source?.close()
  clear()
  if (!name) return
  status.value = 'connecting'
  source = new EventSource(`/api/logs/${encodeURIComponent(name)}`)
  source.onopen = () => { status.value = 'live' }
  source.onmessage = (message) => {
    const line = JSON.parse(message.data) as LogLine
    if (frozen.value) {
      held.value.push(line)
      if (held.value.length > MAX_RAW) held.value.splice(0, held.value.length - MAX_RAW)
    } else {
      append([line])
    }
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

// --- Export des lignes brutes (non fusionnées), affichées ou en attente ---

function exportLog() {
  const lines = [...raw.value, ...held.value]
  if (!lines.length) return
  const text = lines.map(l => `${l.t} ${l.s} ${l.m}`).join('\n') + '\n'
  const stamp = new Date().toISOString().slice(0, 19).replace(/:/g, '-')
  const url = URL.createObjectURL(new Blob([text], { type: 'text/plain;charset=utf-8' }))
  const link = document.createElement('a')
  link.href = url
  link.download = `${selected.value || 'logs'}-${stamp}.log`
  document.body.appendChild(link)
  link.click()
  link.remove()
  setTimeout(() => URL.revokeObjectURL(url), 0)
}

// --- Affichage ---

const visible = computed(() => {
  const needle = filter.value.trim().toLowerCase()
  return needle ? rows.value.filter(l => l.m.toLowerCase().includes(needle)) : rows.value
})

// Suit la fin du flux tant que l'utilisateur ne remonte pas dans l'historique
watch(() => [visible.value.length, visible.value.at(-1)?.count], async () => {
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

// Erreur : fond rouge léger + texte rouge ; avertissement : ambre ; info / debug : texte courant ou atténué.
// Nuances explicites pour garder un contraste suffisant en clair comme en sombre.
const ROW_CLASS: Record<Level, string> = {
  error: 'bg-red-500/8 text-red-700 dark:bg-red-500/12 dark:text-red-300',
  warn: 'text-amber-700 dark:text-amber-300',
  info: 'text-default',
  debug: 'text-muted',
}
const BADGE_CLASS: Record<Level, string> = {
  error: 'bg-red-500/15 text-red-700 dark:text-red-300',
  warn: 'bg-amber-500/15 text-amber-700 dark:text-amber-300',
  info: 'bg-elevated text-dimmed',
  debug: 'bg-elevated text-dimmed',
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
          <UInput v-model="filter" icon="i-lucide-filter" placeholder="Filtrer les lignes…" size="sm" class="w-48" aria-label="Filtrer les lignes" />
          <USelectMenu
            v-model="selected"
            :items="services"
            value-key="value"
            placeholder="Choisir un service"
            icon="i-lucide-container"
            size="sm"
            class="w-56"
            aria-label="Service"
          />
          <UButton
            icon="i-lucide-rotate-cw"
            color="neutral"
            variant="ghost"
            size="sm"
            aria-label="Reconnecter"
            title="Reconnecter"
            @click="connect(selected)"
          />
        </div>
      </div>
    </template>

    <!-- Barre d'outils du flux : actions explicites, libellées -->
    <div class="flex flex-wrap items-center gap-1 border-b border-default px-2 py-1.5">
      <UButton
        :icon="localPaused ? 'i-lucide-play' : 'i-lucide-pause'"
        :label="localPaused ? 'Reprendre' : 'Pause'"
        :aria-pressed="localPaused"
        color="neutral"
        :variant="localPaused ? 'soft' : 'ghost'"
        size="xs"
        @click="localPaused = !localPaused"
      />
      <UButton icon="i-lucide-eraser" label="Effacer" color="neutral" variant="ghost" size="xs" @click="clear" />
      <UButton
        icon="i-lucide-download"
        label="Exporter .log"
        color="neutral"
        variant="ghost"
        size="xs"
        :disabled="!raw.length && !held.length"
        @click="exportLog"
      />
      <span class="ml-auto flex items-center gap-2 px-1 text-xs text-muted tabular-nums" aria-live="polite">
        <span v-if="frozen" class="flex items-center gap-1 text-warning">
          <UIcon name="i-lucide-pause" class="size-3" />
          figé{{ globalPaused && !localPaused ? ' (pause globale)' : '' }}{{ held.length ? ` · ${held.length} en attente` : '' }}
        </span>
        <span v-else-if="rows.length">{{ rows.length }} ligne{{ rows.length > 1 ? 's' : '' }}</span>
      </span>
    </div>

    <div class="relative">
      <div
        ref="viewport"
        class="h-96 overflow-auto bg-muted/40 py-2 font-mono text-xs leading-5"
        role="log"
        aria-label="Flux de logs"
        @scroll="onScroll"
      >
        <p v-if="!visible.length" class="py-8 text-center text-muted">
          {{ selected ? (filter ? 'Aucune ligne ne correspond au filtre.' : 'En attente de logs…') : 'Choisissez un service.' }}
        </p>
        <div
          v-for="line in visible"
          :key="line.id"
          class="flex gap-3 border-l-2 pr-3 pl-3"
          :class="[line.level ? ROW_CLASS[line.level] : 'text-default', line.s === 'err' ? 'border-(--ui-border-accented)' : 'border-transparent']"
          :title="line.s === 'err' ? 'stderr' : 'stdout'"
        >
          <span class="shrink-0 text-dimmed opacity-70 select-none">{{ time(line.t) }}</span>
          <span class="min-w-0 flex-1 whitespace-pre-wrap break-all">
            <span v-if="line.meta" class="text-dimmed opacity-70">{{ line.meta }} </span>
            <span
              v-if="line.levelToken"
              class="mr-1.5 rounded px-1 py-px text-[10px] font-medium uppercase"
              :class="BADGE_CLASS[line.level ?? 'info']"
            >{{ line.levelToken }}</span>
            <span>{{ line.body }}</span>
          </span>
          <span
            v-if="line.count > 1"
            class="h-fit shrink-0 rounded-full bg-elevated px-1.5 text-[10px] leading-4 font-medium text-muted tabular-nums ring-1 ring-default"
            :title="`Message répété ${line.count} fois, dernière occurrence à ${time(line.t)}`"
          >×{{ line.count }}</span>
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

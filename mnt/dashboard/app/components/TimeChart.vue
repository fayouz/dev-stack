<script setup lang="ts">
// Courbes en SVG sur un axe de temps imposé (`domain`) : plusieurs TimeChart empilés
// partagent la même échelle x, le même réticule (v-model:hover-time) et les mêmes marges.
// Étiquettes directes au bout de chaque courbe (valeur courante + nom), survol d'une série :
// les autres passent à 20 % d'opacité (v-model:highlight).
const props = withDefaults(defineProps<{
  series: TimeSeries[]
  domain: [number, number]
  // Nom du graphique, pour les lecteurs d'écran
  label: string
  yMax?: number
  height?: number
  showXAxis?: boolean
  // Seuil tracé en pointillés (null : aucun)
  reference?: number | null
  area?: boolean
  pending?: boolean
}>(), { yMax: 100, height: 110, showXAxis: false, reference: 80, area: false, pending: false })

const hoverTime = defineModel<number | null>('hoverTime', { default: null })
const highlight = defineModel<string | null>('highlight', { default: null })

// --- Dimensions : largeur suivie par ResizeObserver, marges identiques pour tous les graphiques
const root = ref<HTMLElement>()
const width = ref(600)
let observer: ResizeObserver | undefined
onMounted(() => {
  if (root.value) width.value = root.value.clientWidth
  observer = new ResizeObserver(([entry]) => { if (entry) width.value = entry.contentRect.width })
  if (root.value) observer.observe(root.value)
})
onBeforeUnmount(() => observer?.disconnect())

// Écran étroit : seule la valeur reste au bout des courbes (la légende au-dessus nomme les séries)
const narrow = computed(() => width.value < 520)
const M = computed(() => ({ left: 40, right: narrow.value ? 52 : 150, top: 8, bottom: props.showXAxis ? 22 : 6 }))
const plotW = computed(() => Math.max(10, width.value - M.value.left - M.value.right))
const svgH = computed(() => props.height + M.value.top + M.value.bottom)
const plotRight = computed(() => M.value.left + plotW.value)
const baseline = computed(() => M.value.top + props.height)

const span = computed(() => (props.domain[1] - props.domain[0]) || 1)
const x = (t: number) => M.value.left + (t - props.domain[0]) / span.value * plotW.value
const y = (v: number) => baseline.value - Math.min(props.yMax, Math.max(0, v)) / props.yMax * props.height
const withSeconds = computed(() => span.value <= 600_000)

const paths = computed(() => props.series.map((s) => {
  const coords = s.points.map(([t, v]) => `${x(t).toFixed(1)},${y(v).toFixed(1)}`)
  const line = coords.length ? `M${coords.join('L')}` : ''
  const first = s.points[0]
  const last = s.points.at(-1)
  const area = first && last ? `${line}L${x(last[0]).toFixed(1)},${baseline.value}L${x(first[0]).toFixed(1)},${baseline.value}Z` : ''
  return { ...s, line, area, last: last?.[1] ?? null }
}))
// La série mise en avant est dessinée en dernier, au-dessus des autres
const ordered = computed(() => [...paths.value].sort((a, b) => Number(a.key === highlight.value) - Number(b.key === highlight.value)))
const opacity = (key: string) => highlight.value && highlight.value !== key ? 0.2 : 1

// --- Axes : grille horizontale à 0 / moitié / max, 5 repères de temps (grille verticale partout,
// libellés seulement sur le graphique du bas)
const yTicks = computed(() => [0, props.yMax / 2, props.yMax])
const xTicks = computed(() => Array.from({ length: 5 }, (_, i) => {
  const t = props.domain[0] + i * span.value / 4
  return { t, x: x(t), anchor: i === 0 ? 'start' : i === 4 ? 'end' : 'middle' }
}))

// --- Étiquettes directes : décalées pour ne pas se chevaucher (14 px minimum)
const ends = computed(() => {
  const gap = 14
  const items = paths.value
    .filter(p => p.last != null)
    .map(p => ({ key: p.key, name: p.name, color: p.color, value: p.last!, y: y(p.last!) }))
    .sort((a, b) => a.y - b.y)
  for (let i = 1; i < items.length; i++) items[i]!.y = Math.max(items[i]!.y, items[i - 1]!.y + gap)
  const max = svgH.value - 5
  for (let i = items.length - 1; i >= 0; i--) {
    const next = items[i + 1]
    items[i]!.y = Math.min(items[i]!.y, next ? next.y - gap : max)
  }
  return items
})
const shortName = (name: string) => name.length > 16 ? `${name.slice(0, 15)}…` : name

// --- Réticule : aligné sur le point le plus proche, partagé entre graphiques via hoverTime
const times = computed(() => props.series.reduce<[number, number][]>((best, s) => s.points.length > best.length ? s.points : best, []))
const active = ref(false)
const crosshair = computed(() => {
  if (hoverTime.value == null || hoverTime.value < props.domain[0] || hoverTime.value > props.domain[1]) return null
  const rows = paths.value
    .map(s => ({ key: s.key, name: s.name, color: s.color, point: nearestPoint(s.points, hoverTime.value!) }))
    .filter(r => r.point)
    .map(r => ({ ...r, value: r.point![1], cy: y(r.point![1]) }))
  return { x: x(hoverTime.value), time: hoverTime.value, rows: [...rows].sort((a, b) => b.value - a.value) }
})

function snap(t: number) {
  return nearestPoint(times.value, t)?.[0] ?? null
}

function onPointerMove(event: PointerEvent) {
  const rect = (event.currentTarget as SVGSVGElement).getBoundingClientRect()
  const px = event.clientX - rect.left
  if (px < M.value.left || px > plotRight.value) {
    hoverTime.value = null
    active.value = false
    return
  }
  hoverTime.value = snap(props.domain[0] + (px - M.value.left) / plotW.value * span.value)
  active.value = true
}
function onPointerLeave() {
  hoverTime.value = null
  active.value = false
  highlight.value = null
}

// Clavier : flèches pour parcourir les points (Maj : 10 à la fois), Début / Fin, Échap
function onKeydown(event: KeyboardEvent) {
  const list = times.value
  if (!list.length) return
  const index = hoverTime.value == null ? list.length - 1 : list.findIndex(p => p[0] === hoverTime.value)
  const step = event.shiftKey ? 10 : 1
  const moves: Record<string, number> = {
    ArrowLeft: index - step,
    ArrowRight: index + step,
    Home: 0,
    End: list.length - 1,
  }
  if (event.key === 'Escape') {
    hoverTime.value = null
    active.value = false
    return
  }
  const target = moves[event.key]
  if (target === undefined) return
  event.preventDefault()
  hoverTime.value = list[Math.min(list.length - 1, Math.max(0, target))]![0]
  active.value = true
}
function onFocus() {
  hoverTime.value = times.value.at(-1)?.[0] ?? null
  active.value = true
}
function onBlur() {
  hoverTime.value = null
  active.value = false
}

const tooltipStyle = computed(() => {
  if (!crosshair.value) return {}
  const right = crosshair.value.x > width.value / 2
  return right
    ? { left: `${crosshair.value.x - 10}px`, transform: 'translateX(-100%)' }
    : { left: `${crosshair.value.x + 10}px` }
})

const summary = computed(() => `${props.label} : ${paths.value.map(p => `${p.name} ${formatPercent(p.last)}`).join(', ')}. Flèches gauche et droite pour parcourir les valeurs.`)
</script>

<template>
  <div
    ref="root"
    class="relative w-full min-w-0 rounded-md transition-opacity focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
    :class="{ 'opacity-60': pending }"
    tabindex="0"
    role="figure"
    :aria-label="summary"
    @keydown="onKeydown"
    @focus="onFocus"
    @blur="onBlur"
  >
    <svg
      :width="width"
      :height="svgH"
      class="block touch-pan-y overflow-visible select-none"
      aria-hidden="true"
      @pointermove="onPointerMove"
      @pointerleave="onPointerLeave"
    >
      <!-- Grille et axes, discrets -->
      <g>
        <line v-for="tick in xTicks" :key="`x${tick.t}`" :x1="tick.x" :x2="tick.x" :y1="M.top" :y2="baseline" stroke="var(--viz-grid)" />
        <template v-for="tick in yTicks" :key="`y${tick}`">
          <line :x1="M.left" :x2="plotRight" :y1="y(tick)" :y2="y(tick)" :stroke="tick === 0 ? 'var(--viz-axis)' : 'var(--viz-grid)'" />
          <text :x="M.left - 6" :y="y(tick)" text-anchor="end" dominant-baseline="middle" class="fill-(--ui-text-muted) text-[10px] tabular-nums">{{ tick }} %</text>
        </template>
        <template v-if="reference != null && reference < yMax">
          <line :x1="M.left" :x2="plotRight" :y1="y(reference)" :y2="y(reference)" stroke="var(--viz-warning)" stroke-dasharray="4 3" opacity="0.8" />
          <text :x="M.left - 6" :y="y(reference)" text-anchor="end" dominant-baseline="middle" class="fill-(--ui-text-muted) text-[10px] tabular-nums">{{ reference }}</text>
        </template>
        <template v-if="showXAxis">
          <text
            v-for="tick in xTicks"
            :key="`l${tick.t}`"
            :x="tick.x"
            :y="svgH - 4"
            :text-anchor="tick.anchor"
            class="fill-(--ui-text-muted) text-[10px] tabular-nums"
          >
            {{ formatTime(tick.t, withSeconds) }}
          </text>
        </template>
      </g>

      <!-- Séries -->
      <g v-for="s in ordered" :key="s.key" class="transition-opacity duration-150" :opacity="opacity(s.key)">
        <path v-if="area && s.area" :d="s.area" :fill="s.color" opacity="0.12" />
        <path :d="s.line" fill="none" :stroke="s.color" :stroke-width="highlight === s.key ? 2.5 : 2" stroke-linejoin="round" stroke-linecap="round" />
      </g>

      <!-- Réticule partagé -->
      <g v-if="crosshair" pointer-events="none">
        <line :x1="crosshair.x" :x2="crosshair.x" :y1="M.top" :y2="baseline" stroke="var(--ui-text-muted)" stroke-width="1" />
        <circle
          v-for="r in crosshair.rows"
          :key="r.key"
          :cx="crosshair.x"
          :cy="r.cy"
          r="4"
          :fill="r.color"
          stroke="var(--ui-bg)"
          stroke-width="2"
          :opacity="opacity(r.key)"
        />
      </g>

      <!-- Zones de survol des courbes, plus larges que le trait -->
      <path
        v-for="s in paths"
        :key="`hit${s.key}`"
        :d="s.line"
        fill="none"
        stroke="transparent"
        stroke-width="12"
        pointer-events="stroke"
        @pointerenter="highlight = s.key"
        @pointerleave="highlight = null"
      />

      <!-- Étiquettes directes au bout des courbes : trait de couleur + valeur + nom (texte en encre neutre) -->
      <g
        v-for="end in ends"
        :key="`end${end.key}`"
        class="transition-opacity duration-150"
        :opacity="opacity(end.key)"
        @pointerenter="highlight = end.key"
        @pointerleave="highlight = null"
      >
        <title>{{ end.name }} : {{ formatPercent(end.value) }}</title>
        <rect :x="plotRight + 2" :y="end.y - 7" :width="M.right - 4" height="14" fill="transparent" />
        <line :x1="plotRight + 4" :x2="plotRight + 12" :y1="end.y" :y2="end.y" :stroke="end.color" stroke-width="2" stroke-linecap="round" />
        <text :x="plotRight + 16" :y="end.y" dominant-baseline="middle" class="text-[11px] tabular-nums">
          <tspan class="fill-(--ui-text-highlighted) font-semibold">{{ formatPercent(end.value) }}</tspan>
          <tspan v-if="!narrow" dx="5" class="fill-(--ui-text-muted)">{{ shortName(end.name) }}</tspan>
        </text>
      </g>
    </svg>

    <!-- Infobulle : uniquement sur le graphique survolé ; valeur en avant, nom en second -->
    <div
      v-if="active && crosshair"
      class="pointer-events-none absolute top-1 z-10 min-w-36 rounded-md bg-default px-2.5 py-1.5 text-xs shadow-lg ring ring-default"
      :style="tooltipStyle"
      role="status"
      aria-live="polite"
    >
      <p class="mb-1 text-muted tabular-nums">{{ formatTime(crosshair.time, true) }}</p>
      <ul class="flex flex-col gap-0.5">
        <li v-for="r in crosshair.rows" :key="r.key" class="flex items-center gap-2" :class="{ 'opacity-50': highlight && highlight !== r.key }">
          <span class="h-0.5 w-3 shrink-0 rounded" :style="{ background: r.color }" />
          <span class="font-semibold text-highlighted tabular-nums">{{ formatPercent(r.value) }}</span>
          <span class="truncate text-muted">{{ r.name }}</span>
        </li>
      </ul>
    </div>
  </div>
</template>

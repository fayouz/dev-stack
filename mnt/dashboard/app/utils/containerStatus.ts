// État lisible d'un conteneur et résumé quantitatif d'un groupe (projet, catégorie)
interface ContainerLike {
  state: string
  health: string | null
  onDemand: boolean
}

type Tone = 'success' | 'warning' | 'error' | 'neutral'

// Classes de pastille : la couleur double le texte, elle ne le remplace jamais
export const DOT_CLASS: Record<Tone, string> = {
  success: 'bg-success',
  warning: 'bg-warning',
  error: 'bg-error',
  neutral: 'bg-(--ui-border-accented)',
}

/** Conteneur en panne : healthcheck en échec, mort ou en boucle de redémarrage */
export const isBroken = (c: ContainerLike) =>
  c.health === 'unhealthy' || c.state === 'dead' || c.state === 'restarting'

/** Arrêté alors qu'il devrait tourner (un service « à la demande » arrêté est normal) */
export const isStopped = (c: ContainerLike) => c.state !== 'running' && !isBroken(c) && !c.onDemand

export function containerState(c: ContainerLike): { label: string, color: Tone } {
  if (c.state === 'running') {
    if (c.health === 'unhealthy') return { label: 'malade', color: 'error' }
    if (c.health === 'starting') return { label: 'démarrage', color: 'warning' }
    return { label: c.health === 'healthy' ? 'sain' : 'actif', color: 'success' }
  }
  if (c.state === 'restarting') return { label: 'redémarre', color: 'error' }
  if (c.state === 'paused') return { label: 'en pause', color: 'warning' }
  if (c.state === 'dead') return { label: 'mort', color: 'error' }
  return { label: c.onDemand ? 'à la demande' : 'arrêté', color: 'neutral' }
}

const plural = (n: number, word: string) => `${n} ${word}${n > 1 ? 's' : ''}`

/**
 * Micro-indicateur d'un groupe : « 5/5 actifs », « 4/5 actifs — 1 arrêté »,
 * « 3/3 actifs — 1 malade ». Les services à la demande arrêtés ne comptent pas
 * dans l'attendu.
 */
export function groupSummary(containers: ContainerLike[], allStoppedIsNormal = true): { label: string, color: Tone } {
  const expected = containers.filter(c => c.state === 'running' || !c.onDemand)
  const running = containers.filter(c => c.state === 'running').length
  const unhealthy = containers.filter(c => c.state === 'running' && c.health === 'unhealthy').length
  const down = containers.filter(c => c.state === 'dead' || c.state === 'restarting').length
  const stopped = containers.filter(isStopped).length

  const details = [
    unhealthy ? plural(unhealthy, 'malade') : '',
    down ? `${plural(down, 'conteneur')} en panne` : '',
    stopped ? plural(stopped, 'arrêté') : '',
  ].filter(Boolean)
  const label = `${running}/${expected.length} actif${running > 1 ? 's' : ''}${details.length ? ` — ${details.join(', ')}` : ''}`

  if (unhealthy || down) return { label, color: 'error' }
  if (!expected.length) return { label: 'à la demande — arrêté', color: 'neutral' }
  // Application entièrement arrêtée : souvent volontaire, ton neutre (pas pour la stack)
  if (!running && allStoppedIsNormal) return { label: `0/${expected.length} actif — arrêté`, color: 'neutral' }
  if (stopped) return { label, color: 'warning' }
  return { label, color: 'success' }
}

/**
 * Boutons d'action discrets : atténués sur les écrans à survol, pleinement
 * visibles au survol ou au focus de la ligne (`group/row`), toujours visibles
 * sur écran tactile. Jamais masqués : ils restent atteignables au clavier.
 */
export const REVEAL_CLASS = 'transition-opacity [@media(hover:hover)]:opacity-40 group-hover/row:opacity-100 group-focus-within/row:opacity-100 focus-visible:opacity-100'

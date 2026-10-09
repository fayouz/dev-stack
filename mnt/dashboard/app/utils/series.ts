// Série temporelle affichée par TimeChart : points [timestamp ms, valeur en %]
export interface TimeSeries {
  key: string
  name: string
  color: string
  points: [number, number][]
}

/** Heure d'un point ; secondes affichées pour les fenêtres courtes (temps réel) */
export function formatTime(t: number, withSeconds = false) {
  return new Date(t).toLocaleTimeString('fr-FR', withSeconds
    ? { hour: '2-digit', minute: '2-digit', second: '2-digit' }
    : { hour: '2-digit', minute: '2-digit' })
}

/** Point le plus proche de `t` (points triés par temps), par dichotomie */
export function nearestPoint(points: [number, number][], t: number) {
  if (!points.length) return null
  let lo = 0
  let hi = points.length - 1
  while (hi - lo > 1) {
    const mid = (lo + hi) >> 1
    if (points[mid]![0] < t) lo = mid
    else hi = mid
  }
  return Math.abs(points[lo]![0] - t) <= Math.abs(points[hi]![0] - t) ? points[lo]! : points[hi]!
}

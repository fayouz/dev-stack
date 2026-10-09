// Filtres de la liste des conteneurs (partagés entre la vue d'ensemble et ContainerList)
export type ContainerFilter = 'stack' | 'tools' | 'app' | 'problems' | 'updates'

export const FILTER_LABELS: Record<ContainerFilter, string> = {
  stack: 'Stack',
  tools: 'Outils',
  app: 'Applications',
  problems: 'Problèmes',
  updates: 'Mises à jour',
}

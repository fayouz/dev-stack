export type Category = 'stack' | 'tools' | 'app' | 'other'

// Couleurs d'identification (pas de couleurs de statut : elles restent réservées aux états)
export const CATEGORIES: Record<Category, { label: string, description: string, icon: string, color: 'neutral' | 'info' | 'primary' }> = {
  stack: {
    label: 'Stack',
    description: 'Infrastructure de dev : proxy, login, bases, monitoring, sauvegardes',
    icon: 'i-lucide-layers',
    color: 'neutral',
  },
  tools: {
    label: 'Outils',
    description: 'Interfaces utilisées au quotidien',
    icon: 'i-lucide-wrench',
    color: 'info',
  },
  app: {
    label: 'Applications',
    description: 'Projets en développement, regroupés par projet Compose',
    icon: 'i-lucide-app-window',
    color: 'primary',
  },
  other: {
    label: 'Autres',
    description: 'Conteneurs hors Compose : helpers d\'IDE, conteneurs ponctuels',
    icon: 'i-lucide-box',
    color: 'neutral',
  },
}

export const CATEGORY_KEYS = Object.keys(CATEGORIES) as Category[]
// Catégories suivies dans les indicateurs et le menu (« autres » n'y figure pas)
export const MAIN_CATEGORIES: Category[] = ['stack', 'tools', 'app']

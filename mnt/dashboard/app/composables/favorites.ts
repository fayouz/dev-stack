// Conteneurs favoris : simple confort propre à chaque navigateur (localStorage).
// Le stockage peut être indisponible (navigation privée, données bloquées) :
// l'état reste alors en mémoire le temps de la session.
const STORAGE_KEY = 'dashboard:favorites'

function load(): string[] {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    const parsed: unknown = raw ? JSON.parse(raw) : []
    return Array.isArray(parsed) ? parsed.filter((v): v is string => typeof v === 'string') : []
  } catch {
    return []
  }
}

function save(names: string[]) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(names))
  } catch {
    // Stockage indisponible : on garde la liste en mémoire
  }
}

export function useFavorites() {
  // Partagé entre tous les composants (la liste des conteneurs et le tableau des services)
  const list = useState<string[]>('favorites', load)

  const isFavorite = (name: string) => list.value.includes(name)
  function toggle(name: string) {
    list.value = isFavorite(name) ? list.value.filter(n => n !== name) : [...list.value, name].sort()
    save(list.value)
  }

  return { list: readonly(list), isFavorite, toggle }
}

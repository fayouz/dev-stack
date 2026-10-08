import type { WudContainer } from '../updates.get'

// Déclencheur `dockercompose.stack` de WUD : réécrit le tag dans le compose
// (avec une copie .back), tire l'image et recrée le conteneur
const TRIGGER = 'dockercompose/stack'

export default defineEventHandler(async (event) => {
  assertFromDashboard(event)

  // Seul l'ID d'un conteneur que WUD connaît et peut mettre à jour est transmis
  const id = getRouterParam(event, 'id') ?? ''
  const containers = await wudFetch<WudContainer[]>('/api/containers').catch((error: Error) => {
    throw createError({ statusCode: 502, statusMessage: `WUD injoignable : ${error.message}` })
  })
  const container = containers.find(c => c.id === id)
  if (!container) throw createError({ statusCode: 404, statusMessage: 'Conteneur inconnu de WUD' })
  if (!container.updateAvailable) throw createError({ statusCode: 409, statusMessage: `${container.name} est déjà à jour` })

  // WUD ne répond qu'une fois l'image tirée et le conteneur recréé
  await wudFetch(`/api/containers/${id}/triggers/${TRIGGER}`, { method: 'POST', timeout: 15 * 60_000 })
    .catch((error: { data?: { message?: string }, message: string }) => {
      throw createError({ statusCode: 502, statusMessage: error.data?.message ?? error.message })
    })

  return { name: container.name }
})

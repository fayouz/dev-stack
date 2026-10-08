const ACTIONS = ['start', 'stop', 'restart']

export default defineEventHandler(async (event) => {
  assertFromDashboard(event)

  const name = getRouterParam(event, 'name') ?? ''
  const action = getRouterParam(event, 'action') ?? ''
  if (!ACTIONS.includes(action)) {
    throw createError({ statusCode: 400, statusMessage: `Action inconnue : ${action}` })
  }
  if (action === 'stop' && STOP_PROTECTED.includes(name)) {
    throw createError({ statusCode: 403, statusMessage: `${name} ne peut pas être arrêté depuis le dashboard` })
  }

  // On ne passe à l'API que l'ID d'un conteneur existant, jamais la saisie brute
  const container = (await listContainers()).find(c => containerName(c) === name)
  if (!container) {
    throw createError({ statusCode: 404, statusMessage: `Conteneur introuvable : ${name}` })
  }

  // Sans paramètre `t`, Docker applique le stop_grace_period du conteneur (2 min pour Oracle)
  const { dockerActionsHost } = useRuntimeConfig()
  await $fetch(`/containers/${container.Id}/${action}`, {
    baseURL: dockerActionsHost,
    method: 'POST',
    timeout: 180_000,
  })

  return { name, action }
})

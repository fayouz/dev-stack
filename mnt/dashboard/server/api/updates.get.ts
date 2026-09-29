interface WudContainer {
  id: string
  name: string
  image: { name: string, tag: { value: string } }
  updateAvailable: boolean
  updateKind?: { kind: 'tag' | 'digest' | 'unknown', remoteValue?: string, semverDiff?: string }
  result?: { tag?: string }
  error?: { message: string }
}

export default defineEventHandler(async () => {
  const { wudUrl, wudUser, wudPassword } = useRuntimeConfig()
  const containers = await $fetch<WudContainer[]>('/api/containers', {
    baseURL: wudUrl,
    headers: { Authorization: `Basic ${Buffer.from(`${wudUser}:${wudPassword}`).toString('base64')}` },
    timeout: 5000,
  }).catch((error: Error) => {
    throw createError({ statusCode: 502, statusMessage: `WUD injoignable : ${error.message}` })
  })

  return {
    watched: containers.length,
    errors: containers.filter(c => c.error).length,
    updates: containers
      .filter(c => c.updateAvailable)
      .map(c => ({
        name: c.name,
        image: c.image.name.replace(/^library\//, ''),
        current: c.image.tag.value,
        next: c.updateKind?.kind === 'digest' ? 'nouveau build' : c.updateKind?.remoteValue ?? c.result?.tag ?? '?',
        kind: c.updateKind?.kind ?? 'unknown',
        semverDiff: c.updateKind?.semverDiff ?? null,
      }))
      .sort((a, b) => a.name.localeCompare(b.name)),
  }
})

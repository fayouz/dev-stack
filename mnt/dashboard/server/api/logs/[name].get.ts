// Logs d'un conteneur en temps réel, relayés en Server-Sent Events.
// Chaque événement porte une ligne : { t: horodatage ISO, s: 'out' | 'err', m: message }

const TAIL = 200
// Codes de couleur ANSI : inutiles dans le navigateur
const ANSI = /\x1B\[[0-9;?]*[ -/]*[@-~]/g

function parseLine(raw: string, stream: 'out' | 'err') {
  // Avec timestamps=1, Docker préfixe chaque ligne par "2026-09-29T16:00:00.123456789Z "
  const space = raw.indexOf(' ')
  const t = space > 0 ? raw.slice(0, space) : ''
  return { t, s: stream, m: raw.slice(space + 1).replace(ANSI, '').replace(/\r$/, '') }
}

export default defineEventHandler(async (event) => {
  const name = getRouterParam(event, 'name') ?? ''
  const container = (await listContainers()).find(c => containerName(c) === name)
  if (!container) {
    throw createError({ statusCode: 404, statusMessage: `Conteneur introuvable : ${name}` })
  }

  const { dockerHost } = useRuntimeConfig()
  // Sans TTY, Docker multiplexe stdout/stderr avec un en-tête de 8 octets par trame
  const { Config } = await $fetch<{ Config: { Tty: boolean } }>(`/containers/${container.Id}/json`, {
    baseURL: dockerHost,
    timeout: 5000,
  })

  const abort = new AbortController()
  const response = await fetch(
    `${dockerHost}/containers/${container.Id}/logs?follow=1&stdout=1&stderr=1&timestamps=1&tail=${TAIL}`,
    { signal: abort.signal },
  )
  if (!response.ok || !response.body) {
    throw createError({ statusCode: 502, statusMessage: `Logs indisponibles (${response.status})` })
  }

  const stream = createEventStream(event)
  stream.onClosed(() => abort.abort())

  const decoder = { out: new TextDecoder(), err: new TextDecoder() }
  const partial = { out: '', err: '' }
  let buffer = new Uint8Array(0)

  async function emit(kind: 'out' | 'err', bytes: Uint8Array) {
    const text = partial[kind] + decoder[kind].decode(bytes, { stream: true })
    const lines = text.split('\n')
    partial[kind] = lines.pop() ?? ''
    const events = lines.filter(Boolean).map(line => JSON.stringify(parseLine(line, kind)))
    if (events.length) await stream.push(events)
  }

  ;(async () => {
    const reader = response.body!.getReader()
    try {
      while (true) {
        const { done, value } = await reader.read()
        if (done) break
        if (Config.Tty) {
          await emit('out', value)
          continue
        }
        // Démultiplexage : [type, 0, 0, 0, taille (4 octets big-endian)] + contenu
        const merged = new Uint8Array(buffer.length + value.length)
        merged.set(buffer)
        merged.set(value, buffer.length)
        buffer = merged
        while (buffer.length >= 8) {
          const size = new DataView(buffer.buffer, buffer.byteOffset + 4, 4).getUint32(0)
          if (buffer.length < 8 + size) break
          await emit(buffer[0] === 2 ? 'err' : 'out', buffer.subarray(8, 8 + size))
          buffer = buffer.slice(8 + size)
        }
      }
    } catch {
      // Connexion fermée par le client ou arrêt du conteneur
    } finally {
      await stream.close()
    }
  })()

  return stream.send()
})

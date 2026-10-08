/** Appel à l'API de WUD avec le compte local (le login OIDC est réservé au navigateur) */
export function wudFetch<T>(path: string, options: { method?: 'GET' | 'POST', timeout?: number } = {}) {
  const { wudUrl, wudUser, wudPassword } = useRuntimeConfig()
  return $fetch<T>(path, {
    baseURL: wudUrl,
    method: options.method ?? 'GET',
    headers: { Authorization: `Basic ${Buffer.from(`${wudUser}:${wudPassword}`).toString('base64')}` },
    timeout: options.timeout ?? 5000,
  })
}

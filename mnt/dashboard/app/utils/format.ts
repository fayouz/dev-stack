const BYTE_UNITS = ['o', 'Ko', 'Mo', 'Go', 'To']

export function formatBytes(bytes: number | null | undefined) {
  if (bytes == null) return '—'
  let value = bytes
  let unit = 0
  while (value >= 1024 && unit < BYTE_UNITS.length - 1) {
    value /= 1024
    unit++
  }
  return `${value.toFixed(value >= 100 || unit === 0 ? 0 : 1)} ${BYTE_UNITS[unit]}`
}

export function formatPercent(value: number | null | undefined) {
  if (value == null) return '—'
  return `${value.toFixed(value < 10 ? 1 : 0)} %`
}

export function formatDuration(seconds: number | null | undefined) {
  if (seconds == null) return '—'
  const days = Math.floor(seconds / 86400)
  const hours = Math.floor((seconds % 86400) / 3600)
  const minutes = Math.floor((seconds % 3600) / 60)
  if (days) return `${days} j ${hours} h`
  if (hours) return `${hours} h ${minutes} min`
  return `${minutes} min`
}

const relative = new Intl.RelativeTimeFormat('fr', { numeric: 'auto' })

export function formatRelative(iso: string) {
  const seconds = (new Date(iso).getTime() - Date.now()) / 1000
  const abs = Math.abs(seconds)
  if (abs < 60) return relative.format(Math.round(seconds), 'second')
  if (abs < 3600) return relative.format(Math.round(seconds / 60), 'minute')
  if (abs < 86400) return relative.format(Math.round(seconds / 3600), 'hour')
  return relative.format(Math.round(seconds / 86400), 'day')
}

export function formatDate(iso: string) {
  return new Date(iso).toLocaleString('fr-FR', { dateStyle: 'short', timeStyle: 'short' })
}

import { readFile } from 'node:fs/promises'

// Écrit par mnt/restic/scripts/status.sh après chaque sauvegarde
interface BackupStatus {
  lastRun: { at: string, result: 'ok' | 'error' | 'none', message: string }
  snapshots: Array<{
    short_id: string
    time: string
    tags?: string[]
    paths: string[]
    summary?: { total_bytes_processed?: number }
  }>
}

export default defineEventHandler(async () => {
  const { backupStatusFile } = useRuntimeConfig()
  try {
    const status = JSON.parse(await readFile(backupStatusFile, 'utf8')) as BackupStatus
    return {
      available: true as const,
      lastRun: status.lastRun,
      snapshots: status.snapshots
        .map(s => ({
          id: s.short_id,
          time: s.time,
          tags: s.tags ?? [],
          paths: s.paths,
          size: s.summary?.total_bytes_processed ?? null,
        }))
        .sort((a, b) => b.time.localeCompare(a.time)),
    }
  } catch {
    return { available: false as const }
  }
})

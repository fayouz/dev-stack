import { readFile } from 'node:fs/promises'
import { join } from 'node:path'

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
  const { backupStatusDir, backupRequestDir } = useRuntimeConfig()
  // Sauvegarde demandée depuis le dashboard (pas encore prise en charge), puis en cours
  const [requested, running] = await Promise.all([
    fileExists(join(backupRequestDir, 'backup')),
    fileExists(join(backupStatusDir, 'running')),
  ])
  try {
    const status = JSON.parse(await readFile(join(backupStatusDir, 'status.json'), 'utf8')) as BackupStatus
    return {
      available: true as const,
      requested,
      running,
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
    return { available: false as const, requested, running }
  }
})

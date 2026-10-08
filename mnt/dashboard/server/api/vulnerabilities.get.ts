import { readFile } from 'node:fs/promises'
import { join } from 'node:path'

// Écrit par mnt/trivy/scripts/scan.sh après chaque analyse
export interface Vulnerability {
  id: string
  severity: string
  pkg: string
  installed: string
  fixed: string | null
  title: string
}
interface ScanStatus {
  scannedAt: string
  images: Array<{
    image: string
    containers: string[]
    error: string | null
    counts: Record<'CRITICAL' | 'HIGH' | 'MEDIUM' | 'LOW' | 'UNKNOWN', number>
    fixable: number
    top: Vulnerability[]
  }>
}

export default defineEventHandler(async () => {
  const { trivyStatusDir, trivyRequestDir } = useRuntimeConfig()
  const [requested, running] = await Promise.all([
    fileExists(join(trivyRequestDir, 'scan')),
    fileExists(join(trivyStatusDir, 'running')),
  ])
  try {
    const status = JSON.parse(await readFile(join(trivyStatusDir, 'vulnerabilities.json'), 'utf8')) as ScanStatus
    return { available: true as const, requested, running, ...status }
  } catch {
    return { available: false as const, requested, running }
  }
})

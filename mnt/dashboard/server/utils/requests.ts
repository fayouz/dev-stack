import { access, writeFile } from 'node:fs/promises'
import { join } from 'node:path'

// Le dashboard n'a pas le droit d'exécuter de commande dans les autres conteneurs :
// il dépose un fichier de demande que le conteneur concerné (restic, trivy) surveille.

/** Rejette les requêtes qui ne viennent pas du dashboard lui-même (protection CSRF) */
export function assertFromDashboard(event: Parameters<typeof getHeader>[0]) {
  if (getHeader(event, 'x-requested-with') !== 'dashboard') {
    throw createError({ statusCode: 403, statusMessage: 'Requête refusée' })
  }
}

export async function fileExists(path: string) {
  return access(path).then(() => true, () => false)
}

export async function requestJob(dir: string, job: string) {
  await writeFile(join(dir, job), new Date().toISOString()).catch((error: Error) => {
    throw createError({ statusCode: 500, statusMessage: `Demande impossible à déposer : ${error.message}` })
  })
}

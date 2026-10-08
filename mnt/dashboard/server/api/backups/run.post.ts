// Pris en charge par le conteneur restic dans les secondes qui suivent
export default defineEventHandler(async (event) => {
  assertFromDashboard(event)
  await requestJob(useRuntimeConfig().backupRequestDir, 'backup')
  return { requested: true }
})

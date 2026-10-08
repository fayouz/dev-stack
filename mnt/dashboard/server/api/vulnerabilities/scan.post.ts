// Pris en charge par le conteneur trivy dans les secondes qui suivent
export default defineEventHandler(async (event) => {
  assertFromDashboard(event)
  await requestJob(useRuntimeConfig().trivyRequestDir, 'scan')
  return { requested: true }
})

export default defineEventHandler(async () => {
  const [cpu, cores, load1, memTotal, memAvailable, diskSize, diskAvailable, uptime] = await Promise.all([
    promScalar('100 * (1 - avg(rate(node_cpu_seconds_total{mode="idle"}[1m])))'),
    promScalar('count(node_cpu_seconds_total{mode="idle"})'),
    promScalar('node_load1'),
    promScalar('node_memory_MemTotal_bytes'),
    promScalar('node_memory_MemAvailable_bytes'),
    promScalar('max(node_filesystem_size_bytes{mountpoint="/"})'),
    promScalar('max(node_filesystem_avail_bytes{mountpoint="/"})'),
    promScalar('node_time_seconds - node_boot_time_seconds'),
  ])

  return {
    available: cpu !== null,
    cpu,
    cores,
    load1,
    memory: memTotal !== null && memAvailable !== null ? { total: memTotal, used: memTotal - memAvailable } : null,
    disk: diskSize !== null && diskAvailable !== null ? { total: diskSize, used: diskSize - diskAvailable } : null,
    uptime,
  }
})

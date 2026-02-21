import { exec } from 'child_process'
import { promisify } from 'util'
import { readFile } from 'fs/promises'

const execAsync = promisify(exec)

// Track active viewers: map of sessionId -> last seen timestamp
const activeViewers = new Map<string, number>()
const VIEWER_TTL_MS = 35000 // 35s — clients poll every 5s, so 7 missed = gone

async function runCommand(cmd: string): Promise<string> {
  try {
    const { stdout } = await execAsync(cmd)
    return stdout.trim()
  } catch {
    return ''
  }
}

async function getTemperature(): Promise<number | null> {
  try {
    // Try vcgencmd first (Raspberry Pi)
    const temp = await runCommand('vcgencmd measure_temp')
    if (temp) {
      const match = temp.match(/temp=([\d.]+)/)
      if (match) return parseFloat(match[1])
    }

    // Fallback to thermal zone
    const thermal = await readFile('/sys/class/thermal/thermal_zone0/temp', 'utf-8')
    return parseInt(thermal) / 1000
  } catch {
    return null
  }
}

async function getMemory() {
  try {
    const meminfo = await readFile('/proc/meminfo', 'utf-8')
    const lines = meminfo.split('\n')

    const getValue = (key: string) => {
      const line = lines.find(l => l.startsWith(key))
      if (!line) return 0
      return parseInt(line.split(/\s+/)[1]) / 1024 // Convert to MB
    }

    const total = getValue('MemTotal:')
    const free = getValue('MemFree:')
    const buffers = getValue('Buffers:')
    const cached = getValue('Cached:')
    const available = getValue('MemAvailable:')
    const swapTotal = getValue('SwapTotal:')
    const swapFree = getValue('SwapFree:')

    return {
      total: Math.round(total),
      used: Math.round(total - available),
      available: Math.round(available),
      percent: Math.round(((total - available) / total) * 100),
      swap: {
        total: Math.round(swapTotal),
        used: Math.round(swapTotal - swapFree),
        percent: swapTotal > 0 ? Math.round(((swapTotal - swapFree) / swapTotal) * 100) : 0
      }
    }
  } catch {
    return null
  }
}

async function getDisk() {
  try {
    const df = await runCommand('df -h / | tail -1')
    const parts = df.split(/\s+/)
    return {
      total: parts[1],
      used: parts[2],
      available: parts[3],
      percent: parseInt(parts[4])
    }
  } catch {
    return null
  }
}

async function getCpu() {
  try {
    const loadavg = await readFile('/proc/loadavg', 'utf-8')
    const [load1, load5, load15] = loadavg.split(' ').map(parseFloat)

    const cpuinfo = await readFile('/proc/cpuinfo', 'utf-8')
    const cores = (cpuinfo.match(/^processor/gm) || []).length

    return {
      cores,
      load: { load1, load5, load15 },
      percent: Math.min(100, Math.round((load1 / cores) * 100))
    }
  } catch {
    return null
  }
}

async function getUptime() {
  try {
    const uptime = await readFile('/proc/uptime', 'utf-8')
    const seconds = parseFloat(uptime.split(' ')[0])

    const days = Math.floor(seconds / 86400)
    const hours = Math.floor((seconds % 86400) / 3600)
    const minutes = Math.floor((seconds % 3600) / 60)

    if (days > 0) return `${days}d ${hours}h ${minutes}m`
    if (hours > 0) return `${hours}h ${minutes}m`
    return `${minutes}m`
  } catch {
    return null
  }
}

async function getHostname() {
  try {
    return await runCommand('hostname')
  } catch {
    return 'unknown'
  }
}

async function getIpAddress() {
  try {
    const ip = await runCommand("hostname -I | awk '{print $1}'")
    return ip || 'unknown'
  } catch {
    return 'unknown'
  }
}

async function getNodeProcesses() {
  try {
    const ps = await runCommand("ps aux | grep -E 'node|npm' | grep -v grep | wc -l")
    return parseInt(ps) || 0
  } catch {
    return 0
  }
}

export async function GET(request: Request) {
  // Track active viewers by session ID from header
  const sessionId = new URL(request.url).searchParams.get('sid')
  if (sessionId) {
    activeViewers.set(sessionId, Date.now())
    // Prune stale viewers
    for (const [id, ts] of activeViewers) {
      if (Date.now() - ts > VIEWER_TTL_MS) activeViewers.delete(id)
    }
  }

  const [temperature, memory, disk, cpu, uptime, hostname, ip, nodeProcesses] = await Promise.all([
    getTemperature(),
    getMemory(),
    getDisk(),
    getCpu(),
    getUptime(),
    getHostname(),
    getIpAddress(),
    getNodeProcesses()
  ])

  const data = {
    timestamp: new Date().toISOString(),
    system: {
      hostname,
      ip,
      uptime,
      platform: process.platform,
      arch: process.arch,
      nodeVersion: process.version
    },
    temperature,
    memory,
    disk,
    cpu,
    processes: {
      node: nodeProcesses
    },
    viewers: activeViewers.size
  }

  return Response.json(data)
}

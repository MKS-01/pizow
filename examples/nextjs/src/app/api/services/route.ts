import { exec } from 'child_process'
import { promisify } from 'util'

const execAsync = promisify(exec)

async function runCommand(cmd: string): Promise<string> {
  try {
    const { stdout } = await execAsync(cmd)
    return stdout.trim()
  } catch {
    return ''
  }
}

interface ListeningPort {
  port: number
  address: string
  process: string
  pid: number | null
}

interface Pm2Process {
  name: string
  pid: number | null
  status: string
  uptimeSince: number | null
  memoryMB: number
  cpu: number
}

interface SystemdService {
  name: string
  status: string
}

interface NodeProcess {
  pid: number
  memoryMB: number
  script: string
}

export interface ServicesData {
  timestamp: string
  ports: ListeningPort[]
  pm2: Pm2Process[]
  pm2Available: boolean
  systemd: SystemdService[]
  systemdAvailable: boolean
  nodeProcesses: NodeProcess[]
}

async function getListeningPorts(): Promise<ListeningPort[]> {
  const output = await runCommand('ss -tlnp')
  if (!output) return []

  const ports: ListeningPort[] = []
  const lines = output.split('\n').slice(1) // skip header

  for (const line of lines) {
    if (!line.startsWith('LISTEN')) continue

    const portMatch = line.match(/(?:[\d.:*]+):(\d+)\s/)
    if (!portMatch) continue

    const port = parseInt(portMatch[1])
    if (isNaN(port) || port < 3000 || port > 9999) continue

    const addrMatch = line.match(/([\d.]+|\[::\]|\*):(\d+)\s/)
    const address = addrMatch ? addrMatch[1] : '0.0.0.0'

    const processMatch = line.match(/users:\(\("([^"]+)",pid=(\d+)/)
    const processName = processMatch ? processMatch[1] : 'unknown'
    const pid = processMatch ? parseInt(processMatch[2]) : null

    ports.push({ port, address, process: processName, pid })
  }

  return ports
}

async function getPm2Processes(): Promise<{ processes: Pm2Process[]; available: boolean }> {
  const output = await runCommand('pm2 jlist 2>/dev/null')
  if (!output) return { processes: [], available: false }

  try {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const list: any[] = JSON.parse(output)
    const processes: Pm2Process[] = list.map(p => ({
      name: p.name ?? 'unknown',
      pid: p.pid ?? null,
      status: p.pm2_env?.status ?? 'unknown',
      uptimeSince: p.pm2_env?.pm_uptime ?? null,
      memoryMB: p.monit?.memory ? Math.round(p.monit.memory / 1024 / 1024) : 0,
      cpu: p.monit?.cpu ?? 0
    }))
    return { processes, available: true }
  } catch {
    return { processes: [], available: false }
  }
}

const KNOWN_SERVICES = ['nginx', 'caddy', 'mosquitto', 'redis', 'redis-server', 'postgresql', 'bluetooth', 'dnsmasq']

async function getSystemdServices(): Promise<{ services: SystemdService[]; available: boolean }> {
  const hasSystemctl = await runCommand('which systemctl')
  if (!hasSystemctl) return { services: [], available: false }

  const results = await Promise.all(
    KNOWN_SERVICES.map(async name => {
      const status = await runCommand(`systemctl is-active ${name} 2>/dev/null`)
      return { name, status: status || 'unknown' }
    })
  )

  const active = results.filter(s => s.status === 'active')
  return { services: active, available: true }
}

function deriveScriptName(args: string): string {
  if (!args) return 'node'
  // Handle common patterns
  if (args.includes('next-server')) return 'next-server'
  if (args.includes('next start')) return 'next start'
  if (args.includes('npm')) return 'npm'
  // Extract last path component of the first js file argument
  const match = args.match(/(?:^|\s)([\w./\-]+\.js)/)
  if (match) {
    const parts = match[1].split('/')
    return parts[parts.length - 1]
  }
  return 'node'
}

async function getNodeProcesses(): Promise<NodeProcess[]> {
  const output = await runCommand("ps -eo pid,rss,comm,args --no-headers | grep -E '\\bnode\\b|next-server' | grep -v grep")
  if (!output) return []

  const processes: NodeProcess[] = []
  for (const line of output.split('\n')) {
    const trimmed = line.trim()
    if (!trimmed) continue
    const parts = trimmed.split(/\s+/)
    if (parts.length < 2) continue

    const pid = parseInt(parts[0])
    const memoryMB = Math.round(parseInt(parts[1]) / 1024)
    const args = parts.slice(3).join(' ')

    if (isNaN(pid)) continue

    processes.push({ pid, memoryMB, script: deriveScriptName(args) })
  }

  return processes
}

export async function GET() {
  try {
    const [ports, pm2Result, systemdResult, nodeProcesses] = await Promise.all([
      getListeningPorts(),
      getPm2Processes(),
      getSystemdServices(),
      getNodeProcesses()
    ])

    const data: ServicesData = {
      timestamp: new Date().toISOString(),
      ports,
      pm2: pm2Result.processes,
      pm2Available: pm2Result.available,
      systemd: systemdResult.services,
      systemdAvailable: systemdResult.available,
      nodeProcesses
    }

    return Response.json(data)
  } catch {
    const empty: ServicesData = {
      timestamp: new Date().toISOString(),
      ports: [],
      pm2: [],
      pm2Available: false,
      systemd: [],
      systemdAvailable: false,
      nodeProcesses: []
    }
    return Response.json(empty)
  }
}

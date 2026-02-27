'use client'

import { useEffect, useRef, useState } from 'react'

interface ServicesData {
  timestamp: string
  ports: { port: number; address: string; process: string; pid: number | null; connections: number; pm2Name: string | null }[]
  pm2: { name: string; pid: number | null; status: string; uptimeSince: number | null; memoryMB: number; cpu: number }[]
  pm2Available: boolean
  systemd: { name: string; status: string }[]
  systemdAvailable: boolean
  nodeProcesses: { pid: number; memoryMB: number; script: string }[]
}

interface HealthData {
  timestamp: string
  system: {
    hostname: string
    ip: string
    uptime: string | null
    platform: string
    arch: string
    nodeVersion: string
  }
  temperature: number | null
  memory: {
    total: number
    used: number
    available: number
    percent: number
    swap: {
      total: number
      used: number
      percent: number
    }
  } | null
  disk: {
    total: string
    used: string
    available: string
    percent: number
  } | null
  nas: {
    total: string
    used: string
    available: string
    percent: number
  } | null
  network: {
    rxBps: number
    txBps: number
  } | null
  cpu: {
    cores: number
    load: { load1: number; load5: number; load15: number }
    percent: number
  } | null
  processes: {
    node: number
  }
  viewers: number
}

function StatusBadge({ status }: { status: 'ok' | 'warning' | 'critical' }) {
  const colors = {
    ok: 'bg-green-500/20 text-green-400',
    warning: 'bg-yellow-500/20 text-yellow-400',
    critical: 'bg-red-500/20 text-red-400'
  }
  const labels = { ok: 'Healthy', warning: 'Warning', critical: 'Critical' }

  return (
    <span className={`px-3 py-1 rounded-full text-sm font-medium ${colors[status]}`}>
      <span className="inline-block w-2 h-2 rounded-full bg-current mr-2 animate-pulse" />
      {labels[status]}
    </span>
  )
}

function ProgressBar({ percent, color = 'green' }: { percent: number; color?: string }) {
  const colors: Record<string, string> = {
    green: 'bg-green-500',
    yellow: 'bg-yellow-500',
    red: 'bg-red-500',
    blue: 'bg-blue-500'
  }

  const barColor = percent > 80 ? colors.red : percent > 60 ? colors.yellow : colors[color]

  return (
    <div className="w-full bg-zinc-800 rounded-full h-2 overflow-hidden">
      <div
        className={`h-full rounded-full transition-all duration-500 ${barColor}`}
        style={{ width: `${Math.min(100, percent)}%` }}
      />
    </div>
  )
}


function Metric({ label, value, unit, onMouseDown, onMouseUp, onMouseLeave, onTouchStart, onTouchEnd, clickable }: { label: string; value: string | number; unit?: string; onMouseDown?: () => void; onMouseUp?: () => void; onMouseLeave?: () => void; onTouchStart?: () => void; onTouchEnd?: () => void; clickable?: boolean }) {
  return (
    <div className="flex justify-between items-center py-2 border-b border-zinc-800 last:border-0">
      <span className="text-zinc-500 text-xs">{label}</span>
      <span
        className={`font-mono text-xs text-zinc-300 ${clickable ? 'cursor-pointer select-none' : ''}`}
        onMouseDown={onMouseDown} onMouseUp={onMouseUp} onMouseLeave={onMouseLeave}
        onTouchStart={onTouchStart} onTouchEnd={onTouchEnd}
        title={clickable ? 'Hold to reveal' : undefined}
      >
        {value}
        {unit && <span className="text-zinc-500 ml-1">{unit}</span>}
      </span>
    </div>
  )
}

function formatUptime(uptimeSince: number | null): string {
  if (!uptimeSince) return '--'
  const ms = Date.now() - uptimeSince
  const s = Math.floor(ms / 1000)
  const m = Math.floor(s / 60)
  const h = Math.floor(m / 60)
  const d = Math.floor(h / 24)
  if (d > 0) return `${d}d ${h % 24}h`
  if (h > 0) return `${h}h ${m % 60}m`
  if (m > 0) return `${m}m`
  return `${s}s`
}

// Returns animation-duration based on CPU% — faster pulse = higher load
function heartbeatDuration(cpu: number): string {
  if (cpu >= 80) return '0.5s'
  if (cpu >= 50) return '0.9s'
  if (cpu >= 20) return '1.4s'
  return '2.2s'
}

function PulseDot({ color, cpu = 0 }: { color: string; cpu?: number }) {
  return (
    <span className="relative flex-shrink-0 w-2 h-2">
      <span
        className={`absolute inline-flex h-full w-full rounded-full opacity-60 ${color}`}
        style={{ animation: `ping ${heartbeatDuration(cpu)} ease-in-out infinite` }}
      />
      <span className={`relative inline-flex rounded-full h-2 w-2 ${color}`} />
    </span>
  )
}

function SectionLabel({ children, color }: { children: React.ReactNode; color: string }) {
  return (
    <div className={`flex items-center gap-2 mb-2`}>
      <span className={`w-0.5 h-3 rounded-full ${color}`} />
      <p className="text-xs text-zinc-500 uppercase tracking-wider font-semibold">{children}</p>
    </div>
  )
}

function maskIp(ip: string): string {
  const parts = ip.split('.')
  if (parts.length !== 4) return '•••.•••.•••.•••'
  return `${parts[0]}.•••.•••.•••`
}

function formatBps(bps: number): string {
  if (bps >= 1_000_000) return `${(bps / 1_000_000).toFixed(1)} MB/s`
  if (bps >= 1_000) return `${(bps / 1_000).toFixed(1)} KB/s`
  return `${bps} B/s`
}

function deriveProjectName(raw: string): string {
  return raw
    .replace(/[-_](server|app|backend|frontend|api|web|service)$/i, '')
    .replace(/[-_]/g, ' ')
    .replace(/\b\w/g, c => c.toUpperCase())
    .trim() || raw
}

function ServiceRow({
  dot,
  name,
  port,
  badges,
  meta,
}: {
  dot: React.ReactNode
  name: string
  port?: string
  badges?: React.ReactNode
  meta?: React.ReactNode
}) {
  return (
    <div className="flex items-center gap-3 py-2.5 px-3 rounded-lg bg-zinc-800/40 hover:bg-zinc-800/70 transition-colors">
      <div className="flex-shrink-0">{dot}</div>
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2 flex-wrap">
          <span className="text-zinc-100 font-medium text-sm truncate">{name}</span>
          {port && (
            <span className="text-cyan-400 font-mono text-xs bg-cyan-500/10 px-1.5 py-0.5 rounded">
              :{port}
            </span>
          )}
          {badges}
        </div>
        {meta && <div className="flex items-center gap-3 mt-0.5">{meta}</div>}
      </div>
    </div>
  )
}

function MetaChip({ label, value }: { label: string; value: string }) {
  return (
    <span className="text-zinc-500 text-xs font-mono">
      <span className="text-zinc-600">{label} </span>{value}
    </span>
  )
}

function ActiveServicesCard({ services, loading, cpuPercent, showPorts, onStartRevealPorts, onStopRevealPorts }: { services: ServicesData | null; loading: boolean; cpuPercent: number; showPorts: boolean; onStartRevealPorts: () => void; onStopRevealPorts: () => void }) {
  if (loading && !services) {
    return (
      <div className="bg-zinc-900 border border-zinc-800 rounded-xl p-5 h-full">
        <h3 className="text-zinc-400 text-sm font-medium mb-4">Active Services</h3>
        <div className="space-y-2">
          <div className="bg-zinc-800 animate-pulse rounded-lg h-10 w-full" />
          <div className="bg-zinc-800 animate-pulse rounded-lg h-10 w-full" />
          <div className="bg-zinc-800 animate-pulse rounded-lg h-10 w-3/4" />
        </div>
      </div>
    )
  }

  const portByPid = new Map<number, number>()
  for (const p of services?.ports ?? []) {
    if (p.pid) portByPid.set(p.pid, p.port)
  }

  const portPids = new Set((services?.ports ?? []).map(p => p.pid).filter(Boolean))
  const dedupedNodeProcs = (services?.nodeProcesses ?? []).filter(p => !portPids.has(p.pid))

  // Exclude ports that are already represented by a PM2 process
  const pm2Pids = new Set((services?.pm2 ?? []).map(p => p.pid).filter(Boolean))
  const unclaimedPorts = (services?.ports ?? []).filter(p => !p.pid || !pm2Pids.has(p.pid))

  const totalCount = (services?.pm2.length ?? 0) + unclaimedPorts.length +
    (services?.systemd.length ?? 0) + dedupedNodeProcs.length

  return (
    <div className="bg-zinc-900 border border-zinc-800 rounded-xl p-5 flex flex-col md:h-full md:max-h-[85vh]">
      <div className="flex items-center justify-between mb-4 flex-shrink-0">
        <h3 className="text-zinc-400 text-sm font-medium">Active Services</h3>
        <div className="flex items-center gap-2">
          {totalCount > 0 && (
            <span className="text-xs bg-zinc-800 text-zinc-400 font-mono px-2 py-0.5 rounded-full">
              {totalCount} running
            </span>
          )}
          <button
            onMouseDown={onStartRevealPorts} onMouseUp={onStopRevealPorts} onMouseLeave={onStopRevealPorts}
            onTouchStart={onStartRevealPorts} onTouchEnd={onStopRevealPorts}
            className="text-xs text-zinc-600 hover:text-zinc-400 select-none transition-colors"
            title="Hold to reveal ports"
          >
            {showPorts ? '🔓' : '🔒'}
          </button>
        </div>
      </div>

      {totalCount === 0 ? (
        <p className="text-zinc-600 text-sm">No active services detected</p>
      ) : (
        <div className="flex-1 space-y-5 overflow-y-auto">
          {services?.pm2Available && services.pm2.length > 0 && (
            <div>
              <SectionLabel color="bg-violet-500">PM2 Processes</SectionLabel>
              <div className="space-y-1.5 mt-2">
                {services.pm2.map(p => {
                  const dotColor = p.status === 'online' ? 'bg-green-500' : p.status === 'errored' ? 'bg-red-500' : 'bg-yellow-500'
                  const matchedPort = p.pid ? portByPid.get(p.pid) : undefined
                  return (
                    <ServiceRow
                      key={p.name}
                      dot={<PulseDot color={dotColor} cpu={p.cpu} />}
                      name={deriveProjectName(p.name)}
                      port={showPorts && matchedPort ? String(matchedPort) : undefined}
                      badges={
                        <span className={`text-xs font-mono px-1.5 py-0.5 rounded ${
                          p.status === 'online' ? 'bg-green-500/10 text-green-400' :
                          p.status === 'errored' ? 'bg-red-500/10 text-red-400' :
                          'bg-yellow-500/10 text-yellow-400'
                        }`}>{p.status}</span>
                      }
                      meta={
                        <>
                          <MetaChip label="uptime" value={formatUptime(p.uptimeSince)} />
                          <MetaChip label="mem" value={`${p.memoryMB}MB`} />
                          <MetaChip label="cpu" value={`${p.cpu}%`} />
                          {p.pid && <MetaChip label="pid" value={String(p.pid)} />}
                        </>
                      }
                    />
                  )
                })}
              </div>
            </div>
          )}

          {unclaimedPorts.length > 0 && (
            <div>
              <SectionLabel color="bg-cyan-500">Open Ports</SectionLabel>
              <div className="space-y-1.5 mt-2">
                {unclaimedPorts.map(p => (
                  <ServiceRow
                    key={p.port}
                    dot={<PulseDot color="bg-cyan-500" cpu={cpuPercent} />}
                    name={deriveProjectName(p.process)}
                    port={showPorts ? String(p.port) : undefined}
                    meta={p.pid ? <MetaChip label="pid" value={String(p.pid)} /> : undefined}
                  />
                ))}
              </div>
            </div>
          )}

          {services?.systemdAvailable && services.systemd.length > 0 && (
            <div>
              <SectionLabel color="bg-emerald-500">Systemd</SectionLabel>
              <div className="space-y-1.5 mt-2">
                {services.systemd.map(s => (
                  <ServiceRow
                    key={s.name}
                    dot={<PulseDot color="bg-emerald-500" cpu={cpuPercent} />}
                    name={deriveProjectName(s.name)}
                    badges={
                      <span className="text-xs font-mono bg-emerald-500/10 text-emerald-400 px-1.5 py-0.5 rounded">
                        {s.status}
                      </span>
                    }
                  />
                ))}
              </div>
            </div>
          )}

          {dedupedNodeProcs.length > 0 && (
            <div>
              <SectionLabel color="bg-blue-500">Node.js</SectionLabel>
              <div className="space-y-1.5 mt-2">
                {dedupedNodeProcs.map(p => (
                  <ServiceRow
                    key={p.pid}
                    dot={<PulseDot color="bg-blue-500" cpu={cpuPercent} />}
                    name={deriveProjectName(p.script)}
                    meta={
                      <>
                        <MetaChip label="pid" value={String(p.pid)} />
                        <MetaChip label="mem" value={`${p.memoryMB}MB`} />
                      </>
                    }
                  />
                ))}
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  )
}

function TrafficBar({ services, onRefresh }: { services: ServicesData | null; onRefresh: () => void }) {
  const ports = services?.ports ?? []
  // Use pm2Name if available, else fall back to process name; skip 'unknown'
  const projects = ports
    .filter(p => p.process && p.process !== 'unknown')
    .map(p => ({
      port: p.port,
      name: p.pm2Name ? deriveProjectName(p.pm2Name) : deriveProjectName(p.process),
      connections: p.connections,
    }))

  if (projects.length === 0) return null

  return (
    <div className="bg-zinc-900 border border-zinc-800 rounded-xl p-3">
      <div className="flex items-center justify-between mb-2.5">
        <div className="flex items-center gap-1.5">
          <p className="text-zinc-500 text-xs font-medium uppercase tracking-wide">Live Traffic</p>
          <span className="text-zinc-700 text-xs">· TCP established</span>
        </div>
        <button
          onClick={onRefresh}
          className="text-zinc-600 hover:text-zinc-300 transition-colors p-1 rounded"
          title="Refresh traffic"
        >
          <svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8" />
            <path d="M21 3v5h-5" />
            <path d="M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16" />
            <path d="M8 16H3v5" />
          </svg>
        </button>
      </div>
      <div className="flex flex-wrap gap-2">
        {projects.map(p => {
          const active = p.connections > 0
          return (
            <div key={p.port} className="flex items-center gap-2.5 bg-zinc-800/50 rounded-lg px-3 py-2 w-[calc(50%-4px)] md:w-[calc(25%-6px)]">
              <span className="relative flex-shrink-0 w-1.5 h-1.5">
                <span className={`absolute inline-flex h-full w-full rounded-full opacity-60 ${active ? 'bg-green-400 animate-ping' : 'bg-zinc-600'}`} />
                <span className={`relative inline-flex rounded-full w-1.5 h-1.5 ${active ? 'bg-green-400' : 'bg-zinc-600'}`} />
              </span>
              <span className="text-zinc-300 text-xs font-medium truncate flex-1">{p.name}</span>
              <span className="text-zinc-600 font-mono text-xs flex-shrink-0">:{p.port}</span>
              <span className={`font-mono text-sm font-bold flex-shrink-0 ${active ? 'text-green-400' : 'text-zinc-600'}`}>
                {p.connections}
              </span>
            </div>
          )
        })}
      </div>
    </div>
  )
}

// Generate a stable session ID for this browser tab
function getSessionId(): string {
  if (typeof window === 'undefined') return ''
  let sid = sessionStorage.getItem('pizow-sid')
  if (!sid) {
    sid = Math.random().toString(36).slice(2) + Date.now().toString(36)
    sessionStorage.setItem('pizow-sid', sid)
  }
  return sid
}

export default function Dashboard() {
  const [data, setData] = useState<HealthData | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [lastUpdate, setLastUpdate] = useState<Date | null>(null)
  const [services, setServices] = useState<ServicesData | null>(null)
  const [servicesLoading, setServicesLoading] = useState(true)
  const [showIp, setShowIp] = useState(false)
  const [showPorts, setShowPorts] = useState(false)

  const startReveal = () => setShowIp(true)
  const stopReveal = () => setShowIp(false)
  const startRevealPorts = () => setShowPorts(true)
  const stopRevealPorts = () => setShowPorts(false)
  const sidRef = useRef<string>(typeof window !== 'undefined' ? getSessionId() : '')

  const fetchHealth = async () => {
    try {
      const sid = sidRef.current
      const url = sid ? `/api/health?sid=${sid}` : '/api/health'
      const res = await fetch(url)
      if (!res.ok) throw new Error('Failed to fetch')
      const json = await res.json()
      setData(json)
      setError(null)
      setLastUpdate(new Date())
    } catch {
      setError('Failed to fetch health data')
    } finally {
      setLoading(false)
    }
  }

  const fetchServices = async () => {
    try {
      const res = await fetch('/api/services')
      if (!res.ok) throw new Error('Failed to fetch')
      const json = await res.json()
      setServices(json)
    } catch {
      // silently fail — services section will show loading state
    } finally {
      setServicesLoading(false)
    }
  }

  useEffect(() => {
    fetchHealth()
    const interval = setInterval(fetchHealth, 5000)
    return () => clearInterval(interval)
  }, [])

  useEffect(() => {
    fetchServices()
    const interval = setInterval(fetchServices, 15000)
    return () => clearInterval(interval)
  }, [])

  const getOverallStatus = (): 'ok' | 'warning' | 'critical' => {
    if (!data) return 'ok'
    if (data.temperature && data.temperature > 80) return 'critical'
    if (data.temperature && data.temperature > 70) return 'warning'
    if (data.memory && data.memory.percent > 90) return 'critical'
    if (data.memory && data.memory.percent > 80) return 'warning'
    if (data.disk && data.disk.percent > 90) return 'critical'
    if (data.disk && data.disk.percent > 80) return 'warning'
    return 'ok'
  }

  if (loading) {
    return (
      <main className="min-h-screen bg-zinc-950 text-white p-6 flex items-center justify-center">
        <div className="text-zinc-400">Loading...</div>
      </main>
    )
  }

  return (
    <main className="bg-zinc-950 text-white p-4 flex flex-col min-h-screen pb-20">
      <div className="max-w-5xl mx-auto w-full flex flex-col gap-3">

        {/* Header */}
        <header className="flex items-center justify-between flex-shrink-0 py-4">
          <div>
            <h1 className="text-xl font-bold leading-none">PiZoW Monitor</h1>
            <p className="text-zinc-500 text-xs mt-1">
              {data?.system.hostname} •{' '}
              <span
                className="cursor-pointer select-none"
                onMouseDown={startReveal} onMouseUp={stopReveal} onMouseLeave={stopReveal}
                onTouchStart={startReveal} onTouchEnd={stopReveal}
                title="Hold to reveal"
              >
                {showIp ? data?.system.ip : (data?.system.ip ? maskIp(data.system.ip) : '•••.•••.•••.•••')}
              </span>
              {lastUpdate && <span className="ml-1">• {lastUpdate.toLocaleTimeString()}</span>}
            </p>
          </div>
          <StatusBadge status={getOverallStatus()} />
        </header>

        {error && (
          <div className="bg-red-500/10 border border-red-500/20 text-red-400 px-3 py-2 rounded-lg text-sm flex-shrink-0">
            {error}
          </div>
        )}

        {/* Quick Stats */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3 flex-shrink-0">
          {[
            { label: 'Temp', value: data?.temperature ? `${data.temperature.toFixed(1)}°` : '--', color: 'text-green-400' },
            { label: 'Memory', value: `${data?.memory?.percent ?? '--'}%`, color: 'text-blue-400' },
            { label: 'CPU', value: `${data?.cpu?.percent ?? '--'}%`, color: 'text-purple-400' },
            { label: 'Disk', value: `${data?.disk?.percent ?? '--'}%`, color: 'text-orange-400' },
          ].map(({ label, value, color }) => (
            <div key={label} className="bg-zinc-900 border border-zinc-800 rounded-xl p-4 flex items-center gap-3">
              <span className={`text-2xl font-bold font-mono ${color}`}>{value}</span>
              <span className="text-zinc-500 text-sm">{label}</span>
            </div>
          ))}
        </div>

        {/* Main content */}
        <div className="grid grid-cols-1 md:grid-cols-5 gap-3 mt-2 md:mt-0">

          {/* Active Services — fills full right-column height on desktop */}
          <div className="md:col-span-3 md:flex md:flex-col">
            <div className="md:flex-1">
              <ActiveServicesCard services={services} loading={servicesLoading} cpuPercent={data?.cpu?.percent ?? 0} showPorts={showPorts} onStartRevealPorts={startRevealPorts} onStopRevealPorts={stopRevealPorts} />
            </div>
          </div>

          {/* Right column */}
          <div className="md:col-span-2 flex flex-col gap-3">

            {/* System + CPU */}
            <div className="bg-zinc-900 border border-zinc-800 rounded-xl p-4">
              <div className="grid grid-cols-2 gap-x-4">
                <div>
                  <p className="text-zinc-500 text-xs font-medium uppercase tracking-wide mb-2">System</p>
                  <Metric label="IP" value={showIp ? (data?.system.ip ?? '--') : (data?.system.ip ? maskIp(data.system.ip) : '•••.•••.•••')} onMouseDown={startReveal} onMouseUp={stopReveal} onMouseLeave={stopReveal} onTouchStart={startReveal} onTouchEnd={stopReveal} clickable />
                  <Metric label="Uptime" value={data?.system.uptime ?? '--'} />
                  <Metric label="Platform" value={`${data?.system.platform ?? '--'}/${data?.system.arch ?? '--'}`} />
                  <Metric label="Processes" value={data?.processes.node ?? '--'} />
                </div>
                <div>
                  <p className="text-zinc-500 text-xs font-medium uppercase tracking-wide mb-2">CPU</p>
                  <Metric label="Load" value={`${data?.cpu?.percent ?? '--'}%`} />
                  <Metric label="Cores" value={data?.cpu?.cores ?? '--'} />
                  <Metric label="1m avg" value={data?.cpu?.load.load1.toFixed(2) ?? '--'} />
                  <Metric label="5m avg" value={data?.cpu?.load.load5.toFixed(2) ?? '--'} />
                  <Metric label="15m avg" value={data?.cpu?.load.load15.toFixed(2) ?? '--'} />
                </div>
              </div>
              <div className="mt-2 px-0">
                <ProgressBar percent={data?.cpu?.percent ?? 0} />
              </div>
            </div>

            {/* Memory + Disk combined */}
            <div className="bg-zinc-900 border border-zinc-800 rounded-xl p-4">
              <p className="text-zinc-400 text-xs font-medium uppercase tracking-wide mb-3">Memory</p>
              <div className="mb-3">
                <div className="flex justify-between text-xs mb-1">
                  <span className="text-zinc-400">RAM</span>
                  <span className="font-mono">{data?.memory?.used ?? '--'} / {data?.memory?.total ?? '--'} MB</span>
                </div>
                <ProgressBar percent={data?.memory?.percent ?? 0} />
              </div>
              <div className="mb-3">
                <div className="flex justify-between text-xs mb-1">
                  <span className="text-zinc-400">Swap</span>
                  <span className="font-mono">{data?.memory?.swap.used ?? '--'} / {data?.memory?.swap.total ?? '--'} MB</span>
                </div>
                <ProgressBar percent={data?.memory?.swap.percent ?? 0} color="blue" />
              </div>
              <Metric label="Available" value={`${data?.memory?.available ?? '--'} MB`} />

              {/* Disk section inline */}
              <div className="border-t border-zinc-800 mt-3 pt-3">
                <p className="text-zinc-400 text-xs font-medium uppercase tracking-wide mb-3">Disk</p>
                <div className="mb-3">
                  <div className="flex justify-between text-xs mb-1">
                    <span className="text-zinc-400">Usage</span>
                    <span className="font-mono">{data?.disk?.used ?? '--'} / {data?.disk?.total ?? '--'}</span>
                  </div>
                  <ProgressBar percent={data?.disk?.percent ?? 0} />
                </div>
                <Metric label="Free" value={data?.disk?.available ?? '--'} />
              </div>

              {/* NAS section inline — only shown when mounted */}
              {data?.nas && (
                <div className="border-t border-zinc-800 mt-3 pt-3">
                  <div className="flex items-center justify-between mb-3">
                    <div className="flex items-center gap-2">
                      <p className="text-zinc-400 text-xs font-medium uppercase tracking-wide">NAS</p>
                      <span className="text-xs bg-green-500/10 text-green-400 px-1.5 py-0.5 rounded font-mono">mounted</span>
                    </div>
                    <a
                      href={`http://${data.system.ip}:8080`}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="text-xs text-cyan-400 hover:text-cyan-300 bg-cyan-500/10 hover:bg-cyan-500/20 px-2 py-1 rounded transition-colors font-medium"
                    >
                      Browse Files ↗
                    </a>
                  </div>
                  <div className="mb-3">
                    <div className="flex justify-between text-xs mb-1">
                      <span className="text-zinc-400">Usage</span>
                      <span className="font-mono">{data.nas.used} / {data.nas.total}</span>
                    </div>
                    <ProgressBar percent={data.nas.percent} color="blue" />
                  </div>
                  <Metric label="Free" value={data.nas.available} />
                </div>
              )}
            </div>

          </div>
        </div>

        {/* Network throughput */}
        {data?.network && (
          <div className="bg-zinc-900 border border-zinc-800 rounded-xl p-3">
            <div className="flex items-center gap-1.5 mb-2.5">
              <p className="text-zinc-500 text-xs font-medium uppercase tracking-wide">Network</p>
              <button type="button" className="relative group flex items-center text-zinc-600 hover:text-zinc-400 cursor-help transition-colors focus:outline-none">
                <svg xmlns="http://www.w3.org/2000/svg" width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                  <circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/>
                </svg>
                <span className="pointer-events-none absolute left-1/2 -translate-x-1/2 bottom-full mb-2 w-56 rounded-lg bg-zinc-800 border border-zinc-700 px-3 py-2 text-xs text-zinc-300 leading-relaxed opacity-0 group-hover:opacity-100 transition-opacity duration-150 z-50 shadow-xl">
                  Live throughput across all active network interfaces (wlan0, eth0). Updates every 5s. Shows bytes transferred since last poll.
                  <span className="absolute left-1/2 -translate-x-1/2 top-full w-0 h-0 border-x-4 border-x-transparent border-t-4 border-t-zinc-700" />
                </span>
              </button>
            </div>
            <div className="flex gap-3">
              <div className="flex-1 flex items-center gap-2.5 bg-zinc-800/50 rounded-lg px-3 py-2">
                <span className="text-green-400 text-xs font-mono">↓</span>
                <span className="text-zinc-400 text-xs">Download</span>
                <span className="text-green-400 font-mono text-sm font-bold ml-auto">{formatBps(data.network.rxBps)}</span>
              </div>
              <div className="flex-1 flex items-center gap-2.5 bg-zinc-800/50 rounded-lg px-3 py-2">
                <span className="text-blue-400 text-xs font-mono">↑</span>
                <span className="text-zinc-400 text-xs">Upload</span>
                <span className="text-blue-400 font-mono text-sm font-bold ml-auto">{formatBps(data.network.txBps)}</span>
              </div>
            </div>
          </div>
        )}

        {/* Full-width traffic bar */}
        <div className="mb-4">
          <TrafficBar services={services} onRefresh={fetchServices} />
        </div>

      </div>

      {/* Footer — fixed to bottom */}
      <footer className="fixed bottom-0 left-0 right-0 text-center py-2 bg-zinc-950/80 backdrop-blur-sm border-t border-zinc-900">
        <span className="text-zinc-600 text-xs inline-flex items-center gap-1.5">
          <span role="img" aria-label="alien">👽</span>
          <span><span className="text-zinc-500 font-medium">MKS</span> · Build with <span className="text-zinc-500 font-medium">Claude</span> · {new Date().getFullYear()}</span>
        </span>
      </footer>
    </main>
  )
}

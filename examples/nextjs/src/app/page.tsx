'use client'

import { useEffect, useState } from 'react'

interface ServicesData {
  timestamp: string
  ports: { port: number; address: string; process: string; pid: number | null }[]
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
  cpu: {
    cores: number
    load: { load1: number; load5: number; load15: number }
    percent: number
  } | null
  processes: {
    node: number
  }
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


function Metric({ label, value, unit, onClick, clickable }: { label: string; value: string | number; unit?: string; onClick?: () => void; clickable?: boolean }) {
  return (
    <div className="flex justify-between items-center py-2 border-b border-zinc-800 last:border-0">
      <span className="text-zinc-500">{label}</span>
      <span className={`font-mono ${clickable ? 'cursor-pointer select-none' : ''}`} onClick={onClick} title={clickable ? 'Click to toggle' : undefined}>
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

function deriveProjectName(raw: string): string {
  // strip common suffixes like "-server", "_app", etc. and title-case
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

const SERVICES_COLLAPSE_LIMIT = 5

function ActiveServicesCard({ services, loading, cpuPercent }: { services: ServicesData | null; loading: boolean; cpuPercent: number }) {
  const [expanded, setExpanded] = useState(false)

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

  const portPids = new Set((services?.ports ?? []).map(p => p.pid).filter(Boolean))
  const dedupedNodeProcs = (services?.nodeProcesses ?? []).filter(p => !portPids.has(p.pid))

  const totalCount = (services?.ports.length ?? 0) + (services?.pm2.length ?? 0) +
    (services?.systemd.length ?? 0) + dedupedNodeProcs.length

  const portByPid = new Map<number, number>()
  for (const p of services?.ports ?? []) {
    if (p.pid) portByPid.set(p.pid, p.port)
  }

  const needsExpand = totalCount > SERVICES_COLLAPSE_LIMIT

  return (
    <div className="bg-zinc-900 border border-zinc-800 rounded-xl p-5 md:h-full flex flex-col">
      <div className="flex items-center justify-between mb-4 flex-shrink-0">
        <h3 className="text-zinc-400 text-sm font-medium">Active Services</h3>
        <div className="flex items-center gap-2">
          {totalCount > 0 && (
            <span className="text-xs bg-zinc-800 text-zinc-400 font-mono px-2 py-0.5 rounded-full">
              {totalCount} running
            </span>
          )}
          {needsExpand && (
            <button
              onClick={() => setExpanded(e => !e)}
              className="text-xs text-zinc-500 hover:text-zinc-300 transition-colors px-2 py-0.5 rounded border border-zinc-700 hover:border-zinc-500"
            >
              {expanded ? 'collapse' : `+${totalCount - SERVICES_COLLAPSE_LIMIT} more`}
            </button>
          )}
        </div>
      </div>

      {totalCount === 0 ? (
        <p className="text-zinc-600 text-sm">No active services detected</p>
      ) : (
        <div className={`flex-1 space-y-5 ${needsExpand && !expanded ? 'overflow-hidden' : 'overflow-auto'}`}
          style={needsExpand && !expanded ? { maxHeight: `${SERVICES_COLLAPSE_LIMIT * 44}px` } : undefined}>
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
                      port={matchedPort ? String(matchedPort) : undefined}
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

          {services && services.ports.length > 0 && (
            <div>
              <SectionLabel color="bg-cyan-500">Open Ports</SectionLabel>
              <div className="space-y-1.5 mt-2">
                {services.ports.map(p => (
                  <ServiceRow
                    key={p.port}
                    dot={<PulseDot color="bg-cyan-500" cpu={cpuPercent} />}
                    name={deriveProjectName(p.process)}
                    port={String(p.port)}
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

export default function Dashboard() {
  const [data, setData] = useState<HealthData | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [lastUpdate, setLastUpdate] = useState<Date | null>(null)
  const [services, setServices] = useState<ServicesData | null>(null)
  const [servicesLoading, setServicesLoading] = useState(true)
  const [showIp, setShowIp] = useState(false)

  const fetchHealth = async () => {
    try {
      const res = await fetch('/api/health')
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
    <main className="bg-zinc-950 text-white p-4 flex flex-col md:h-screen md:overflow-hidden">
      <div className="max-w-5xl mx-auto w-full flex flex-col gap-3 md:h-full">

        {/* Header */}
        <header className="flex items-center justify-between flex-shrink-0">
          <div>
            <h1 className="text-xl font-bold leading-none">PiZoW Monitor</h1>
            <p className="text-zinc-500 text-xs mt-1">
              {data?.system.hostname} •{' '}
              <span className="cursor-pointer select-none" onClick={() => setShowIp(v => !v)} title={showIp ? 'Hide IP' : 'Show IP'}>
                {showIp ? data?.system.ip : '•••.•••.•••.•••'}
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
        <div className="grid grid-cols-1 md:grid-cols-5 gap-3 md:flex-1 md:min-h-0">

          {/* Active Services */}
          <div className="md:col-span-3 md:min-h-0">
            <ActiveServicesCard services={services} loading={servicesLoading} cpuPercent={data?.cpu?.percent ?? 0} />
          </div>

          {/* Right column */}
          <div className="md:col-span-2 flex flex-col gap-3 md:min-h-0">

            {/* System + CPU */}
            <div className="bg-zinc-900 border border-zinc-800 rounded-xl p-4 md:flex-1">
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <p className="text-zinc-400 text-xs font-medium uppercase tracking-wide mb-3">System</p>
                  <Metric label="IP" value={showIp ? (data?.system.ip ?? '--') : '•••.•••.•••'} onClick={() => setShowIp(v => !v)} clickable />
                  <Metric label="Uptime" value={data?.system.uptime ?? '--'} />
                  <Metric label="Platform" value={`${data?.system.platform ?? '--'}/${data?.system.arch ?? '--'}`} />
                  <Metric label="Node.js" value={data?.system.nodeVersion ?? '--'} />
                  <Metric label="Processes" value={data?.processes.node ?? '--'} />
                </div>
                <div>
                  <p className="text-zinc-400 text-xs font-medium uppercase tracking-wide mb-3">CPU</p>
                  <div className="mb-3">
                    <div className="flex justify-between text-xs mb-1">
                      <span className="text-zinc-400">Load</span>
                      <span className="font-mono">{data?.cpu?.percent ?? '--'}%</span>
                    </div>
                    <ProgressBar percent={data?.cpu?.percent ?? 0} />
                  </div>
                  <Metric label="Cores" value={data?.cpu?.cores ?? '--'} />
                  <Metric label="1m avg" value={data?.cpu?.load.load1.toFixed(2) ?? '--'} />
                  <Metric label="5m avg" value={data?.cpu?.load.load5.toFixed(2) ?? '--'} />
                  <Metric label="15m avg" value={data?.cpu?.load.load15.toFixed(2) ?? '--'} />
                </div>
              </div>
            </div>

            {/* Memory */}
            <div className="bg-zinc-900 border border-zinc-800 rounded-xl p-4 md:flex-1">
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
            </div>

            {/* Disk */}
            <div className="bg-zinc-900 border border-zinc-800 rounded-xl p-4 md:flex-1">
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

          </div>
        </div>

        {/* Footer */}
        <footer className="flex-shrink-0 text-center py-1">
          <span className="text-zinc-600 text-xs inline-flex items-center gap-1.5">
            <span role="img" aria-label="alien">👽</span>
            <span><span className="text-zinc-500 font-medium">MKS</span> · Made with <span className="text-zinc-500 font-medium">Claude</span></span>
          </span>
        </footer>

      </div>
    </main>
  )
}

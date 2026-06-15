# Dashboard skill

Use this skill when editing or reviewing `examples/nextjs/src/app/page.tsx` or the API routes in `examples/nextjs/src/app/api/`.

---

## What this is

Single-page Next.js 15 dashboard for the Pi Zero 2W home server. One `page.tsx` (client component), two API routes (`/api/health`, `/api/services`). No component files — keep it that way unless the file exceeds ~900 lines.

---

## Colour system (zinc dark)

| Role | Token |
|---|---|
| Page background | `bg-zinc-950` |
| Card background | `bg-zinc-900` |
| Card border (default) | `border-zinc-800` |
| Card border (tinted) | `border-{color}-900/40` — matches the card's metric colour |
| Muted text | `text-zinc-500` |
| Subdued text | `text-zinc-600` |
| Primary text | `text-zinc-300` |
| Bright text | `text-zinc-100` |
| Mono values | `font-mono text-xs` |

Metric colours by card: Temp = green, Memory = blue, CPU = purple, Disk = orange, Viewers = pink.

---

## Component inventory

| Component | Purpose |
|---|---|
| `StatusBadge` | Header health pill (ok / warning / critical) |
| `ProgressBar` | Horizontal fill bar — colour auto-shifts at 60%/80% |
| `Metric` | Key-value row with optional hold-to-reveal |
| `PulseDot` | Coloured dot for service rows. `breathe` prop enables a slow 2s opacity pulse (online PM2 only) |
| `SectionLabel` | Vertical accent bar + uppercase section title |
| `ServiceRow` | Service entry with dot, name, optional port badge, meta chips |
| `MetaChip` | `label value` in monospace — used inside ServiceRow meta |
| `ActiveServicesCard` | Full left-column services panel (PM2 / Open Ports / Systemd / Node.js) |
| `TempGaugeCard` | SVG arc gauge for temperature. 30–85°C range, 270° sweep, green→yellow→red |
| `NetworkSparklineCard` | Download/upload sparklines with live peak tracking |
| `Sparkline` | SVG path + gradient fill for network samples |

---

## Animation rules (Emil Kowalski "minimum animation" principle)

**Allowed:**
- `dot-breathe` CSS class — 2s opacity pulse on online PM2 dots, gated by `prefers-reduced-motion`
- `net-ping` CSS class — ping on network activity indicator, fires only when `hasTraffic`, gated by `prefers-reduced-motion`
- `transition-[width] duration-200` on ProgressBar — scoped, under 300ms
- `active:scale-[0.97] transition-transform duration-100` on interactive buttons/spans
- `transition-colors` on hover states
- `animate-pulse` on skeleton loaders (transient — disappears once data loads)

**Banned:**
- `animate-ping` directly (use `net-ping` class instead, which is gated)
- `animate-pulse` on persistent UI elements (status dots, badges)
- `transition-all` — always scope to the specific property
- Any duration > 300ms on UI transitions
- JS `setInterval`-driven animation (the ping/pulse must stay in CSS)

Both custom animation keyframes live in `globals.css` under `@media (prefers-reduced-motion: no-preference)`.

---

## Polling intervals

| Endpoint | Client interval | Server TTL cache |
|---|---|---|
| `/api/health` | 5 s | none (reads `/proc/*`, already cheap) |
| `/api/services` | 15 s | 12 s module-level cache |

The Pi is the server — minimise shell execs. `/proc/*` reads are free; `exec()` calls are not.

---

## Pi-specific constraints

- No client-side charting libraries (Chart.js, Recharts, etc.) — SVG paths only
- No heavy dependencies — keep `package.json` lean (Next + React + Tailwind only)
- The network sparkline keeps 30 samples (150s window) — don't increase this
- `backdrop-blur-sm` is fine on the fixed footer (GPU-composited, not JS)
- The `prevNet` module-level variable in `health/route.ts` is intentional — it tracks cumulative bytes across requests to compute bytes/sec delta

---

## Viewer tracking

`/api/health?sid=<sessionId>` tracks active browser tabs. Session ID is generated in `sessionStorage` on first load (`getSessionId()`). The server prunes sessions after 35s of inactivity (`VIEWER_TTL_MS`). Viewers count is shown in the pink stat card.

---

## Security UX

- IP address is masked by default (`maskIp`) — hold to reveal (mousedown/touchstart)
- Port numbers are hidden by default — hold lock icon in Active Services to reveal
- Neither is stored in state beyond the hold duration

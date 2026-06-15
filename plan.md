# PiZoW Plan

---

## 2026-06-15 — Dashboard UX optimisation + Pi-side caching

**Status: done** — branch `ui-optimisation`. Three-part polish pass: animation discipline, services API caching, and visual hierarchy improvements.

### Context

The dashboard runs on a Pi Zero 2W (512MB RAM, 4-core ARM @1GHz). The current `page.tsx` has 5 indefinitely-looping CSS animations — `animate-ping` fires on every service row dot with no `prefers-reduced-motion` gating. The services API re-executes 10+ shell processes on every 15s poll with no caching. Temperature is displayed as a flat number with no visual severity gauge. Design follows Emil Kowalski's principle: _"the best animation is no animation"_ — motion must serve a purpose (feedback, spatial orientation) or be cut entirely.

### Design

1. **Animation cleanup (page.tsx)**
   - `PulseDot`: replace `animate-ping` with a static dot. The ping conveys nothing — it isn't triggered by an event, it just loops. Keep the `bg-*` colour to communicate status. For `online` PM2 processes only, add a very subtle `opacity` pulse (not ping) at `2s` duration, gated behind `@media (prefers-reduced-motion: no-preference)`.
   - `StatusBadge` dot: same — replace `animate-pulse` with static dot. The badge label ("Healthy / Warning / Critical") already communicates state.
   - `NetworkSparklineCard` activity indicator: keep the ping here — it fires only when `hasTraffic` (rxBps > 500 || txBps > 500), which is event-driven and purposeful. Gate it with `prefers-reduced-motion`.
   - `ProgressBar`: change `transition-all duration-500` → `transition-[width] duration-200` (scoped property, under 300ms limit).
   - Reveal buttons (IP, ports lock icon): add `active:scale-[0.97] transition-transform duration-100` for tactile press feedback (Emil tip #1).
   - Loading skeleton `animate-pulse`: keep — it's transient and purposeful (signals loading state).

2. **Services API caching (services/route.ts)**
   - Add a module-level `cache: { data: ServicesData; ts: number } | null` with `CACHE_TTL_MS = 12_000`.
   - On `GET`: if cache is fresh (`Date.now() - cache.ts < CACHE_TTL_MS`), return cached response immediately. Otherwise re-run all execs and populate cache.
   - Set `Cache-Control: max-age=12, stale-while-revalidate=3` on the response.
   - Result: 8 `systemctl` execs + `pm2 jlist` + `ps` run at most once per 12s instead of on every client poll.

3. **Temperature gauge (page.tsx)**
   - Replace the flat `Temp` stat card with a circular SVG arc gauge. Arc goes 0→270° (¾ circle). Range: 30°C (cold) → 85°C (throttle limit). Color: `#4ade80` → `#facc15` → `#f87171` blended via inline style at runtime. Label shows `°C` value centred in the arc.
   - This is the only card that gets this treatment — temperature is the one metric with a hard ceiling that's meaningful to visualise.

4. **Stat card polish (page.tsx)**
   - Quick Stats grid: make the 5 cards slightly denser — reduce padding from `p-4` to `p-3`, tighten font size from `text-2xl` to `text-xl`. Add a subtle per-card colour tint on the border (`border-green-900/40` for Temp, etc.) that matches the value colour. This replaces the current flat `border-zinc-800` on all cards.
   - `Viewers` card: add a tiny `●` indicator that pulses (gated by `prefers-reduced-motion`) when `viewers > 1`.

5. **Dashboard skill (.claude/skills/dashboard.md)**
   - Document: zinc dark colour system, component inventory, animation rules in use, polling intervals, Pi-specific constraints (no heavy JS libs, no client-side charting libraries).
   - Intent: future changes should reference this skill rather than re-reading page.tsx from scratch.

### Files

- `examples/nextjs/src/app/page.tsx` (modified): animation cleanup, temp gauge, stat card polish
- `examples/nextjs/src/app/api/services/route.ts` (modified): TTL cache + Cache-Control header
- `.claude/skills/dashboard.md` (new): design system doc for this dashboard

### Out of scope

- Splitting `page.tsx` into sub-components (files)
- Any charting library (Chart.js, Recharts, etc.)
- Dark/light mode toggle
- WebSocket or SSE — polling stays as-is
- Changes to `health/route.ts` — it's already efficient
- Any change to the Next.js build config or deployment scripts

### Verification

1. Open dashboard in browser. Confirm no indefinitely-looping animations are visible at rest (no ping/pulse on service dots or status badge).
2. Toggle network traffic on the Pi. Confirm the network indicator ping fires only when `hasTraffic` is true.
3. Resize browser to check responsive layout hasn't regressed (mobile 1-col, desktop 5-col).
4. Set OS to "reduce motion". Confirm all remaining animations stop.
5. On Pi: watch server logs during 30s window — confirm services API is called ≤3 times but shell execs fire only once (TTL cache hit logged or verifiable via response timestamp staying the same for 12s).
6. Check temperature gauge arc renders at room temp (~40°C → arc ≈1/3 filled, green). Simulate high temp in API response (`data.temperature = 82`) and confirm arc colour shifts to red.
7. Press the IP reveal button — confirm `scale(0.97)` press effect is visible.

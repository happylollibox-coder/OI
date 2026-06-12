# Dashboard React — CLAUDE.md

## Stack
- React 19 + Vite 7 + TypeScript 5.9 (strict) + Tailwind CSS 4 + Recharts 3
- Icons: Lucide React | Export: XLSX | E2E: Playwright

## Architecture

### Data Flow
```
BigQuery → Cube.js (:4000) → useCubeData → useUnifiedData → components
                                              ↑ fallback
                              /data/*.json → useData (useJsonData)
```
- `useUnifiedData()` is the single entry point — merges Cube + JSON
- Cube queries: POST `/cubejs-api/v1/load` with "Continue wait" polling (2s retry, max 20)
- Static JSON served from `../dashboard/data/` via Vite middleware

### Routing
- No react-router — `useState<PageId>` in App.tsx, Sidebar calls `onNav()`
- 15 pages: home, actions, peak, family, learn, kwds, log, health, experiment, ads, strategies, admin, do, brand, plan

### State Management
- Context + Hooks only (no Redux/Zustand)
- **Providers:** FiltersProvider, DoQueueProvider, PageSummaryProvider
- **Persistence:** localStorage for filters, theme, queue, thresholds, ground-truths

### Custom Hooks
| Hook | Purpose |
|------|---------|
| `useUnifiedData` | Main data orchestrator (Cube + JSON merge) |
| `useCubeData` | Cube.js query execution + row mapping (~1100 lines) |
| `useData` | JSON file fetching fallback |
| `useFilters` | Global filters context (family, product, period) |
| `useDoQueue` | Action queue — bid changes, negations (localStorage) |
| `useTheme` | Dark/light toggle, persists to localStorage |
| `useGroundTruth` | Experiment validation rules (API + localStorage fallback) |
| `useConclusions` | Business insights (API + localStorage fallback) |
| `useThresholds` | User-set warning thresholds |
| `useViewMode` | Admin/Simple view toggle — gates nav pages (USER_VISIBLE_PAGES) and, via `isAdmin`, extra columns/diagnostics (localStorage) |

## Styling

### Design Tokens (CSS vars in index.css)
- Surfaces: `--color-base`, `--color-card`, `--color-surface`
- Borders: `--color-border`, `--color-border-strong`
- Text: `--color-text`, `--color-muted`, `--color-subtle`, `--color-faint`
- Accents: `--color-positive` (green), `--color-negative` (red), `--color-warning` (amber)
- Typography: `--text-hero: 24px`, `--text-title: 20px`, `--text-body: 14px`, `--text-label: 12px`

### Dark/Light Mode
- Default: dark theme via CSS vars
- Light: `.light-mode` class on `<html>` overrides vars
- Always use CSS vars, never hardcode colors (we had a light-mode bug from this)

## API Endpoints
| Target | Proxy | Purpose |
|--------|-------|---------|
| Cube.js :4000 | `/cubejs-api/*` | Analytics queries |
| Cloud Run Flask | `/api/*` | Plans, ground-truths, conclusions |
| Vite middleware | `/data/*.json` | Static dashboard data |

## Key Types (types.ts)
- `DashboardData` — union of all data arrays
- `SummaryRow`, `TrendRow`, `ActionRow`, `ExperimentRow` — core data shapes
- `CoachDecisionRow`, `CoachTermRow`, `HotSignalRow` — AI/coach outputs
- `FamilyName` — 'Lollibox' | 'LolliME' | 'Bottle' | 'Fresh'
- `GlobalFilters` — family, product, periodMode, seasonality, etc.
- `DoQueueItem` — queued bid change with targeting details

## Conventions
- Functional components only, hooks for all logic
- `Card` component wraps all surfaces
- Numbers use `font-mono`, labels use sans-serif
- Formatters: `fM()` (money), `fP()` (percent), `fR()` (ROAS) from utils.ts
- Charts use `chartTheme.ts` which references CSS vars
- Strategies defined in `src/strategies/` — one file per strategy type

## Dev Servers
```bash
cd cube && npm run dev          # Cube.js on :4000
npm run dev                      # Vite on :5173
# Python refresh_data.py writes JSON to dashboard/data/
```

## Testing
- E2E: Playwright (Firefox) — `tests/e2e/`
- Unit: Vitest — `src/**/*.test.ts(x)`
- Run: `npm test` (vitest) | `npx playwright test` (E2E)

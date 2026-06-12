# OI — Open Tasks

> Updated: 2026-06-12 · Owner: Ori
> Recently closed: PPC close-the-loop ✅ · secret rotation + fail-closed secrets ✅ ·
> /api JWT lockdown + stale services deleted ✅ · admin/simple view toggle ✅ ·
> repo hygiene (archive) ✅ · all committed & deployed.

## 🟠 HIGH — do next

### 1. Coach learns from verdicts
Feed `V_PPC_ACTION_OUTCOMES` verdict rates into `SP_SUGGEST_THRESHOLD*` so the coach
tunes `DE_COACH_THRESHOLDS` from real results. This is the step that builds trust in
the coacher. Plumbing exists on both ends — needs the wiring + a review surface
(show suggested threshold changes before applying).
**Effort:** ~1 day. **Wait:** verdicts need ~2 weeks of uploads to be meaningful; the SP wiring can be built now.

### 2. Reconcile the data-lag contradiction
Ori says ads lag is 1–2 days; `ADS_COACH_DECISION_MATRIX.md` and `V_ADS_COACH_DATA`
assume 4 days (3-day lag-safety look-ahead). Affects coach MONITOR guards AND how
early outcome verdicts can be judged (currently −2d cutoff in `V_PPC_ACTION_OUTCOMES`).
**Effort:** decision + small SQL/doc change. Needs Ori's confirmation of the real lag.

### 3. Simple-mode column gating
The ADMIN/SIMPLE toggle ships, but pages don't hide expert columns yet. Use
`useViewMode().isAdmin` to gate: decision-trace chips, 8w internals, lag ROAS,
thresholds on ACTIONS → ADS → KEYWORDS (in that order).
**Effort:** ~half day per page.

### 4. HOME period sync
Header week vs metric-card week mismatch ("are ads broken?" confusion). One period
everywhere; grey out lagged cells with "data arrives in X days" instead of $0.
**Effort:** ~half day.

### 5. Reason tags on urgent actions
Per-action diagnostic chip: `low CTR (0.3%)` · `high CPC ($1.70)` · `wrong ASIN` —
tells the fix, not just the problem. (Top ask from the PPC audit.)
**Effort:** ~half day (signals already exist in coach data).

## 🟡 MEDIUM

### 6. Daily/weekly digest to WhatsApp or Telegram
Cloud Scheduler (API not yet enabled) → new cloud function → BigQuery → message with
real numbers (yesterday's profit, alerts, pending DO items). **Blocked on:** Ori picks
channel (Telegram = 1hr free; WhatsApp via Twilio = half day + template approval).

### 7. Forecast-aware AWD min/max (before Q4!)
SUPPLY min/max limits derive from trailing 30-day velocity — entering October on
September velocity under-stocks. Wire `V_FORECAST_DEMAND` into the Shipment Engine
suggestion. **Effort:** ~1 day.

### 8. Brand-defense SQP impression share
Specced in `strategy_tracking_framework.md`, not built. Brand defense is currently
judged by ROAS — the wrong metric. Auto-extract brand terms from SQP (incl.
misspellings), chart share % vs spend. **Effort:** ~1–2 days.

### 9. Daily-routine checklist on HOME
Lag-aware "Today" checklist: check alerts → review actions → export/upload bulksheet →
mark uploaded. Makes the daily flow teachable to a second user. **Effort:** ~half day.

### 10. Lint debt (~60 errors)
Feature batches were committed `--no-verify` (code predates the eslint setup). Mostly
`no-explicit-any`, some unused vars, a few setState-in-effect. Until cleared, commits
touching those files need `--no-verify`. **Effort:** ~1 day mechanical.

### 11. Retire DE_BULKSHEET_UPLOADS
Half-built prior attempt (`/api/bulksheet-uploads` endpoint live, dashboard never
called it) — superseded by `FACT_PPC_CHANGE_LOG`. Backfill any rows worth keeping,
then drop per ARCHIVE_POLICY. **Effort:** ~1 hour.

## 🟢 LOW / later

12. **PlanPage/KpiPage split** — 4.1k/3.5k-line files; HMR chokes. Split + tests for
    bulksheet generation (money-touching code).
13. **URL routing** — bookmarkable pages / shareable deep links (no react-router today).
14. **Mobile pass** — phone-checkable HOME/ALERTS while traveling.
15. **Amazon Ads API write integration** — replace manual bulksheet upload; do AFTER
    change-log verdicts prove decision quality, so automated changes are logged+scored
    from day one.
16. **Leftover scratch** — `cube/test-cube*.js`, `dashboard-react` root test scripts → archive.
17. **Two-person auth cleanup** — `ALLOWED_USERS` is hardcoded in app.py; move to env var.

## ⚠️ Standing notes

- Secrets live in `OI/.env` (gitignored): `CUBEJS_API_SECRET`, `SECRET_KEY` — required
  by `deploy_all.sh`; rotating them logs everyone out (re-login via Google).
- Local dev: Flask pinned to :5050 (AirPlay owns 5000); `data-entry-app/.env` pins the
  local dev secret. Never point dev proxies at prod again.
- All dashboard `/api` calls must use `apiFetch` (see `architecture/API_AUTH.md`).

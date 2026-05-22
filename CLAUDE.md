# Project Constitution — Ori Intelligence (OI)

## Identity
- **Project:** Ori Intelligence (OI)
- **Owner:** Ori
- **Mission:** Improve net profit per product — Amazon Ads + Seller analytics platform on GCP.
- **Protocol:** B.L.A.S.T. (Blueprint → Link → Architect → Stylize → Trigger)
- **Architecture:** A.N.T. 3-layer (Architecture SOPs → Navigation/Reasoning → Tools)

---

## Integrations

| Service | Purpose | Status |
|---------|---------|--------|
| Google BigQuery | Primary data warehouse (`onyga-482313.OI`) | ✅ Active |
| GCP Cloud Run | Hosts Flask data-entry app + Cube.js | ✅ Active |
| GCP Cloud Functions | Background automation (exchange rates, hot-folder) | ✅ Active |
| Cube.js | Semantic analytics API between dashboard and BigQuery | ✅ Active |
| Google OAuth (Authlib) | Authentication for Flask data-entry app | ✅ Active |
| Amazon Seller Central | Source of Search Query Performance (SQP) data | ✅ Active |
| Amazon Ads API | Source of Ads campaign / keyword performance data | ✅ Active |

---

## BigQuery

**Project:** `onyga-482313` | **Dataset:** `OI` | **Location:** `US`

### Naming Convention
| Prefix | Type |
|--------|------|
| `V_SRC_` | Interface / Fivetran-managed external views |
| `V_` | Internal analytics views |
| `DIM_` | Dimension tables |
| `FACT_` | Fact tables |
| `DE_` | Data-entry tables (user-entered) |
| `SP_` | Stored procedures |
| `FN_` | UDFs / remote functions |

### Key Tables

**FACT_AMAZON_ADS** — `date DATE, asin STRING, campaign_name STRING, ad_spend FLOAT, impressions INT64, clicks INT64, orders INT64, sales FLOAT`

**SQP (Search Query Performance)** — `week DATE, asin STRING, search_query STRING, impressions INT64, clicks INT64, cart_adds INT64, purchases INT64`

**DIM_PRODUCT** — `asin STRING, product_family STRING, title STRING, sku STRING, total_cost FLOAT`

**DE_PURCHASE_ORDERS** — `id STRING, po_number STRING, supplier STRING, order_date DATE, status STRING, total_amount FLOAT`

### Write Patterns
- **Inserts:** `load_table_from_json([row], table_ref, job_config)` — check `job.errors`
- **Updates:** Parameterized `UPDATE ... WHERE id = @id` via `QueryJobConfig`
- **Reads:** `client.query(...).result()` → `[dict(row) for row in results]`

### Rules
- Every new BigQuery object must be registered in `config.yaml`
- Never run destructive SQL without explicit user confirmation

---

## Tech Stack

### React Dashboard (`dashboard-react/`)
- React 19, Vite 7, TypeScript, Tailwind CSS 4, Recharts, Lucide React
- No React Router — routing via `useState` in `App.tsx`
- Data: `useUnifiedData()` → `useCubeData()` when `VITE_CUBE_API_URL` set, else static JSON
- Filters: `useFilters()` inside `FiltersProvider`
- **Measure naming:** `Ads` prefix for Ads-source data; `SQP` prefix for Search Query Performance data

### Cube.js (`cube/schema/`)
- One `.js` file per cube; defines `sql`, `measures`, `dimensions`, optional `joins`
- Fully qualified BQ names: `` `onyga-482313.OI.TABLE` ``
- Local dev: `cd cube && npm run dev` → port 4000

### Flask Data-Entry (`data-entry-app/`)
- Flask 3 + Gunicorn, Google OAuth via Authlib
- No ORM — raw BigQuery client (`google-cloud-bigquery`)
- Caching: `@cache_result(ttl_seconds=N)`, always call `clear_data_cache()` after any write
- Auth: `@login_required` decorator; allowlist in `ALLOWED_USERS`
- Required env: `SECRET_KEY`, `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `GCP_PROJECT_ID`, `BIGQUERY_DATASET`

### Cloud Functions (`cloud-functions/`)
- Node.js — exchange rate fetcher, hot-folder processor

---

## Behavioral Rules

1. **Data-First:** Never write tools until payload shape is confirmed here. Halt and ask if business logic is ambiguous.
2. **No guessing:** If a rule is missing from this file, stop and ask.
3. **SOPs first:** Update `architecture/` before changing code.
4. **Atomic tools:** All execution via deterministic Python scripts in `tools/`. LLM reasoning for routing only.
5. **Intermediates:** Use `.tmp/`. Never commit `.tmp/` contents.
6. **Secrets:** Always in `.env`. Never hardcoded.
7. **config.yaml:** Register every new BigQuery object there.

---

## Directory Layout

```
OI/
├── CLAUDE.md                # This file — Project Constitution
├── config.yaml              # Source of truth for all BigQuery objects
├── task_plan.md             # Phase checklist
├── findings.md              # Discoveries & constraints
├── progress.md              # Audit trail
├── .env                     # Secrets (never committed)
├── architecture/            # Layer 1 — Technical SOPs
├── tools/                   # Layer 3 — Deterministic Python scripts
├── .tmp/                    # Ephemeral intermediates (never committed)
├── cube/schema/             # Cube.js schemas (one file per cube)
├── dashboard-react/src/     # React 19 + Vite + TypeScript + Tailwind 4
│   ├── pages/               # One file per page
│   ├── components/          # Shared UI components
│   ├── hooks/               # useCubeData, useFilters, useUnifiedData
│   └── types.ts             # DashboardData and all shared types
├── data-entry-app/          # Flask 3 + Gunicorn on Cloud Run
│   ├── app.py               # Routes + main app
│   └── templates/           # Jinja2 templates
├── scripts/bigquery/        # All BigQuery SQL objects
│   ├── interface_views/     # V_SRC_* views
│   ├── views/               # V_* analytics views
│   ├── tables/              # DIM_*, FACT_*, DE_* DDL
│   ├── procedures/          # SP_* stored procedures
│   ├── functions/           # FN_* UDFs
│   └── migrations/          # Versioned incremental migrations
├── cloud-functions/         # GCP Cloud Functions (Node.js)
└── deployment/              # Shell scripts; aligned with config.yaml
```

---

## Key Config

| Key | Value |
|-----|-------|
| GCP Project | `onyga-482313` |
| BigQuery Dataset | `OI` |
| Cube API (local) | port `4000` — `cd cube && npm run dev` |
| Dashboard dev | `VITE_CUBE_API_URL=http://localhost:4000` |

---

## Current Phase Status (B.L.A.S.T.)

| Phase | Status |
|-------|--------|
| 0 — Initialization | ✅ Complete |
| 1 — Blueprint | ✅ Complete |
| 2 — Link | ✅ Complete (BigQuery live: 116 objects) |
| 3 — Architect | 🔲 In progress — SOPs + tools pending |
| 4 — Stylize | 🔲 Ongoing — dashboard KPIs + charts |
| 5 — Trigger | 🔲 Pending — scheduled orchestration |

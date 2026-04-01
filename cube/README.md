# Cube.js – OI Dashboard Business Layer

Cube connects the OI dashboard to BigQuery. Schema: `cube/schema/`.

## Prerequisites

1. **BigQuery migration** (one-time):

   ```bash
   bq query --use_legacy_sql=false --project_id=onyga-482313 < ../scripts/bigquery/migrations/MIGRATE_DIM_BUSINESS_CONCLUSIONS_AND_GROUND_TRUTHS.sql
   ```

2. **Dashboard env**: Set `VITE_CUBE_API_URL` (e.g. `http://localhost:4000` or Cloud Run URL) when building the React app so it fetches from Cube instead of static JSON.

## Local development

**Option A – From project root (OI folder):**
```bash
cd cube
npm run dev
# On OneDrive: use npm run dev:onetime so Cube Store uses /tmp
```

**Option B – From anywhere (use the cube folder path):**
```bash
cd "/Users/ori/Library/CloudStorage/OneDrive-HappyLolliLTD/Develop/OI/cube"
npm run dev
```

**Option C – Run script (from inside the cube folder):**
```bash
./run.sh
```

When you see `Cube API server is listening on 4000`, open [http://localhost:4000](http://localhost:4000).

**If Cube seems stuck:** The project is in OneDrive; Cube Store cannot lock files there. Use `npm run dev:onetime` or set `CUBESTORE_DATA_DIR=/tmp/cube-oi-cubestore` in `.env` so Cube Store data lives outside OneDrive. If you still have issues, ensure `bq-key.json` exists and ports 4000/3030 are free.

**Pre-aggregations (faster loads):** Summary, WeeklyTrends, and MonthlyTrends have pre-aggregations. After starting Cube, open http://localhost:4000 → Build tab → click "Build" for each cube. First build is slow; subsequent dashboard loads use cache and return in milliseconds.

**Docker (alternative):**
```bash
docker compose up -d
```

## Environment

| Variable | Description |
|----------|-------------|
| `CUBEJS_DB_BQ_PROJECT_ID` | BigQuery project (default: onyga-482313) |
| `CUBEJS_DB_BQ_KEY_FILE` | Path to service account JSON |
| `CUBEJS_DB_BQ_CREDENTIALS` | Base64-encoded key (for Cloud Run) |
| `CUBEJS_DB_BQ_LOCATION` | Dataset location (default: US) |
| `VITE_CUBE_API_URL` | Cube API URL (dashboard; e.g. `https://cube-xxx.run.app`) |

## Cloud Run deploy

```bash
# Option A: Cloud Build
gcloud builds submit --config=cloudbuild.yaml .

# Option B: Manual
docker build -t gcr.io/onyga-482313/cube .
docker push gcr.io/onyga-482313/cube
gcloud run deploy cube --image gcr.io/onyga-482313/cube --platform managed --region us-central1
```

**Required**: Set `CUBEJS_DB_BQ_CREDENTIALS` in Cloud Run (base64 of service account JSON) or use Secret Manager.

## Orchestration

Cube reads from BigQuery; no separate refresh step. Data freshness follows BigQuery tables. To refresh:

1. Run `SP_ORCHESTRATE_DAILY_REFRESH` (or equivalent) to update BigQuery.
2. Cube queries hit BigQuery directly; no Cube-specific refresh.

## Schema

- `Ads` – FACT_AMAZON_ADS (ads_7d)
- `Product` – DIM_PRODUCT
- `Sqp` – FACT_AMAZON_SEARCH_PERFORMANCE_WEEKLY (sqp_weekly)
- `Experiment` – DIM_EXPERIMENT
- `ExperimentDaily` – FACT_EXPERIMENT_DAILY (experiment_weekly)
- `ChangeLog` – DIM_EXPERIMENT_CHANGE_LOG (change_log)
- `Holidays` – DIM_US_HOLIDAYS (upcoming, peak)
- `Summary` – pre-aggregated 7d by family
- `WeeklyTrends` / `MonthlyTrends` – pre-aggregated by family
- `ExperimentTermRecommendations` – actions, drivers, keyword_product_map
- `ExperimentTemplates` – strategies page

See [docs/SCHEMA_EXPORT.md](../docs/SCHEMA_EXPORT.md) for full BigQuery mapping.

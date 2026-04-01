---
description: Post-change verification — always check Cube then Vite, restart if needed
---
// turbo-all

# Dashboard Testing Workflow

After every dashboard change (React, Cube schema, SQL view), run this flow **in order**.

## Step 1 — Check Cube (port 4000)

```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:4000/cubejs-api/v1/load
```

- **If 400** → Cube is running ✅, go to Step 2.
- **If 000 or connection refused** → Cube is down. Restart:

```bash
cd cube && nohup npm run dev > /tmp/cube.log 2>&1 &
sleep 10
curl -s -o /dev/null -w "%{http_code}" http://localhost:4000/cubejs-api/v1/load
```

- Verify it returns 400 before proceeding. If still down, check `/tmp/cube.log` for errors.

## Step 2 — Check Vite (port 5173)

Only proceed after Cube is confirmed running.

```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:5173
```

- **If 200** → Vite is running ✅, go to Step 3.
- **If 000 or connection refused** → Vite is down. Restart:

```bash
cd dashboard-react && npm run dev
```

- Verify it returns 200 before proceeding.

## Step 3 — Verify data in browser

1. Open `http://localhost:5173` in browser.
2. Confirm the page loads **with real data** (not "No summary data").
3. Check the specific page you changed.
4. Take a screenshot as proof.

## Step 4 — TypeScript check

```bash
cd dashboard-react && npx tsc --noEmit
```

- Must return zero errors.

## Troubleshooting

- If SQL views were changed, deploy first:
  ```bash
  cat scripts/bigquery/views/<VIEW>.sql | bq query --project_id=onyga-482313 --use_legacy_sql=false --max_rows=0
  ```
- If Cube schema changed, restart Cube (Step 1).
- Always confirm **data loads** in the browser — a running server with no data is NOT "working".

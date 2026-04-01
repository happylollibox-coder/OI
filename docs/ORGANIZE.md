# OI workspace – organize & work productively

Use this as a checklist to get your changes under control and start working in an organized way.

---

## 1. What’s in “changes” (untracked)

| Category        | Items |
|----------------|-------|
| **Config / root** | `.funcignore`, `.gitignore`, `config.yaml`, `Makefile`, `README.md` |
| **Docs**        | `docs/`, `plan-productivity.html` |
| **Scripts / SQL** | `scripts/`, `setup_bigquery_schedule.sql`, `setup_daily_orchestrator.sql` |
| **Apps**        | `dashboard/`, `dashboard-react/`, `data-entry-app/` |
| **Cloud**       | `cloud-functions/`, `deployment/` |
| **Business / BI** | `Amazon Business/`, `POWER BI/` |
| **Archive**     | `archive/` |

`data-entry-app.zip` is ignored via `.gitignore` (artifact).

---

## 2. Suggested commit order (logical groups)

Do these in order so history stays clear. Run from repo root.

```bash
# 1) Project foundation
git add .gitignore .funcignore README.md config.yaml Makefile

# 2) Documentation
git add docs/ plan-productivity.html ORGANIZE.md

# 3) BigQuery / data pipeline
git add scripts/ setup_bigquery_schedule.sql setup_daily_orchestrator.sql

# 4) Deployment & cloud
git add deployment/ cloud-functions/

# 5) Dashboards & apps (code only; node_modules/venv stay ignored)
git add dashboard/ dashboard-react/ data-entry-app/

# 6) Business & BI assets
git add "Amazon Business/" "POWER BI/"

# 7) Archive (if you want it in repo)
git add archive/
```

Then commit each group with a clear message, e.g.:

```bash
git commit -m "chore: add project config, gitignore, README"
git commit -m "docs: add docs and productivity plan"
# ... etc.
```

Or stage everything and make **one** commit:

```bash
git add .
git status   # confirm no secrets or .zip
git commit -m "chore: track project structure, docs, scripts, dashboards, deployment"
```

---

## 3. Quick productivity habits

- **One focus area per session** – e.g. “today: BigQuery views” or “today: dashboard-react”.
- **Small commits** – commit after each logical change (fix, feature, or refactor).
- **Branch for features** – e.g. `git checkout -b feature/experiment-dashboard` before bigger work.
- **Use the plan** – open `plan-productivity.html` when you need priorities and next steps.
- **README as map** – `README.md` documents BigQuery layout and where views/live; keep it updated when you add objects.

---

## 4. Repo layout (from README)

```
├── README.md, config.yaml, Makefile
├── scripts/bigquery/     # interface_views, procedures, tables, views
├── docs/                 # trade dress, guides, reports
├── dashboard/            # legacy dashboard (data + refresh_data.py)
├── dashboard-react/      # React dashboard (src/, public/)
├── data-entry-app/       # Python app (templates, excel_templates)
├── cloud-functions/      # fetch-exchange-rates, hot-folder-processor
├── deployment/           # migration/orchestrator scripts
├── Amazon Business/      # business assets
├── POWER BI/             # Power BI measures
└── archive/              # archived docs/scripts/data
```

---

## 5. Before you push

- Run `git status` and `git diff --staged` to confirm what’s included.
- Ensure no `service-account.json`, `.key`, or real credentials are staged.
- If you use a remote: `git push -u origin main` (or your branch name).

You’re set to work in an organized way: group your commits, use the plan, and keep the README in sync with the repo.

# CPC Strategy → Net Profit Analysis

Exploratory analysis: which CPC strategy (raise / lower / hold) makes the most
ads-attributed net profit, per parent product, per calendar part.

Spec: `docs/superpowers/specs/2026-06-25-cpc-strategy-net-profit-analysis-design.md`

## Run
```bash
cd /Users/ori/Develop/OI
.venv/bin/python -m tools.analysis.cpc_strategy_profit.run_all
```
Outputs: `.tmp/cpc_strategy/` (CSVs + charts) and `architecture/CPC_STRATEGY_FINDINGS_2026-06.md`.

## Test
```bash
.venv/bin/python -m pytest tools/analysis/cpc_strategy_profit/tests -v
```

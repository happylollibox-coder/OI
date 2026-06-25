# tools/analysis/cpc_strategy_profit/run_all.py
"""End-to-end: base → regimes → power → rank/merge → recommend → charts → findings doc."""
import pandas as pd
from . import config as C
from .build_base import build_base
from .regimes import assign_regimes, summarize_regime_segments
from .power import build_power_matrix
from .analyze import rank_strategies, merge_segments
from .recommend import build_recommendations, coacher_recent_moves, compare_to_coacher
from .charts import render_all

def run():
    if not C.BASE_CSV.exists():
        build_base()
    base = pd.read_csv(C.BASE_CSV, parse_dates=["date"])

    seg_frames = []
    for _, grp in base.groupby(["campaign_id", "target_key"], sort=False):
        seg_frames.append(summarize_regime_segments(assign_regimes(grp)))
    segs = pd.concat(seg_frames, ignore_index=True)
    segs.to_csv(C.REGIMES_CSV, index=False)

    cells = build_power_matrix(segs)
    cells.to_csv(C.POWER_CSV, index=False)

    ranked = rank_strategies(cells)
    merged = merge_segments(ranked)
    rec = compare_to_coacher(build_recommendations(ranked), coacher_recent_moves())
    rec.to_csv(C.RECS_CSV, index=False)

    render_all(cells, segs)
    write_findings(segs, cells, rec, merged)
    print("done. findings:", C.FINDINGS_DOC)

def write_findings(segs, cells, rec, merged):
    n_conc = int((cells.verdict == "CONCLUSIVE").sum())
    lines = [
        "# CPC Strategy → Net Profit — Findings (2026-06)", "",
        f"_Generated from {len(segs):,} regime-segments across "
        f"{segs.parent_name.nunique()} parents; "
        f"{n_conc}/{len(cells)} cells statistically conclusive._", "",
        "> Observational analysis — associational, not causal. See spec.", "",
        "## Recommended CPC strategy per parent × calendar part", "",
    ]
    if rec.empty:
        lines.append("_No CONCLUSIVE cells — not enough data to recommend. Relax thresholds in config.py._")
    else:
        lines.append(
            rec[["parent_name", "calendar_segment", "recommended_strategy", "winner_npd",
                 "confidence", "coacher_bias", "agrees_with_coacher"]]
            .to_markdown(index=False)
        )
    lines += [
        "",
        "## Power coverage (where we can vs cannot conclude)", "",
        cells.groupby(["parent_name", "verdict"]).size().unstack(fill_value=0).to_markdown(),
        "",
        "## Charts", "",
        *[f"- `{p.relative_to(C.ROOT)}`" for p in sorted(C.CHARTS_DIR.glob('*.png'))],
    ]
    C.FINDINGS_DOC.write_text("\n".join(lines))

if __name__ == "__main__":
    run()

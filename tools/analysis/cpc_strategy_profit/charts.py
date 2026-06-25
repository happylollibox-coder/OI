# tools/analysis/cpc_strategy_profit/charts.py
"""Per-parent charts: net-profit-per-day by strategy, and CPC vs net profit."""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from . import config as C

def chart_npd_by_strategy(cells, parent: str):
    sub = cells[(cells.parent_name == parent) & (cells.verdict == "CONCLUSIVE")]
    if sub.empty:
        return None
    agg = sub.groupby("strategy")["net_profit_per_day"].median().sort_values()
    fig, ax = plt.subplots(figsize=(7, 4))
    agg.plot.barh(ax=ax, color="#3b7")
    ax.set_title(f"{parent}: median net profit / day by CPC strategy")
    ax.set_xlabel("net profit per active day ($)")
    ax.axvline(0, color="k", lw=0.8)
    fig.tight_layout()
    path = C.CHARTS_DIR / f"npd_by_strategy_{parent}.png"
    fig.savefig(path, dpi=110); plt.close(fig)
    return path

def chart_cpc_vs_profit(segs, parent: str):
    sub = segs[segs.parent_name == parent]
    if sub.empty:
        return None
    fig, ax = plt.subplots(figsize=(7, 4))
    ax.scatter(sub["cpc"], sub["net_profit_per_day"], s=12, alpha=0.5)
    ax.set_title(f"{parent}: CPC vs net profit / day (regime-segments)")
    ax.set_xlabel("CPC ($)"); ax.set_ylabel("net profit per active day ($)")
    ax.axhline(0, color="k", lw=0.8)
    fig.tight_layout()
    path = C.CHARTS_DIR / f"cpc_vs_profit_{parent}.png"
    fig.savefig(path, dpi=110); plt.close(fig)
    return path

def render_all(cells, segs):
    C.CHARTS_DIR.mkdir(parents=True, exist_ok=True)
    made = []
    for parent in sorted(segs.parent_name.dropna().unique()):
        for fn in (chart_npd_by_strategy(cells, parent), chart_cpc_vs_profit(segs, parent)):
            if fn:
                made.append(fn)
    print(f"wrote {len(made)} charts to {C.CHARTS_DIR}")
    return made

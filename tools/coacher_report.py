"""Generate a self-contained 'This Week' HTML report from the live coacher views.
Writes .tmp/coacher_this_week.html — open it in any browser. Run by refresh_coacher.sh."""
import subprocess, json, datetime, html, pathlib

PROJECT = "onyga-482313"
OUT = pathlib.Path(__file__).resolve().parents[1] / ".tmp" / "coacher_this_week.html"

def q(sql):
    o = subprocess.run(["bq", f"--project_id={PROJECT}", "query", "--use_legacy_sql=false", "--format=json", sql],
                       capture_output=True, text=True)
    if o.returncode:
        raise SystemExit((o.stderr or "") + (o.stdout or "") or "bq failed (no message)")
    return json.loads(o.stdout) if o.stdout.strip() else []

def f(v, money=True):
    try:
        n = float(v)
    except (TypeError, ValueError):
        return "—"
    s = f"${abs(n):,.0f}" if money else f"{n:g}"
    return ("−" + s) if n < 0 else s

def sev_color(sev):
    return {"ESCALATE": "#b91c1c", "WATCH": "#b45309"}.get(sev, "#475569")

def np_color(v):
    try:
        return "#15803d" if float(v) > 0 else ("#b91c1c" if float(v) < 0 else "#475569")
    except (TypeError, ValueError):
        return "#475569"

def main():
    esc = q("SELECT parent_name,trigger,severity,actual_net,recommended_action "
            "FROM `onyga-482313.OI.V_PLAN_ESCALATION` ORDER BY severity,parent_name")
    plan = q("SELECT parent_name, STRING_AGG(DISTINCT LOWER(purpose), ' · ') purposes, "
             "COUNT(*) cells, ROUND(SUM(planned_spend),0) spend, ROUND(MAX(expected_net_profit),0) exp_np "
             "FROM `onyga-482313.OI.DE_WEEKLY_PLAN` WHERE horizon='CURRENT' GROUP BY 1 ORDER BY 1")
    now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")

    esc_rows = "".join(
        f'<div class="alert" style="border-left-color:{sev_color(e["severity"])}">'
        f'<span class="pill" style="color:{sev_color(e["severity"])}">{html.escape(e["severity"].lower())}</span>'
        f'<div class="who"><b>{html.escape(e["parent_name"])}</b> '
        f'<span class="sub">· {html.escape(e["trigger"].replace("_"," ").lower())}</span></div>'
        f'<div class="num" style="color:{np_color(e["actual_net"])}">{f(e["actual_net"])}</div>'
        f'<div class="act">{html.escape(e["recommended_action"])}</div></div>'
        for e in esc) or '<div class="sub">No escalations — everything on plan.</div>'

    plan_rows = "".join(
        f'<tr><td><b>{html.escape(p["parent_name"])}</b></td><td class="sub">{html.escape(p["purposes"] or "")}</td>'
        f'<td class="r">{p["cells"]}</td><td class="r">{f(p["spend"])}</td>'
        f'<td class="r" style="color:{np_color(p["exp_np"])}">{f(p["exp_np"])}</td></tr>'
        for p in plan)

    doc = f"""<!doctype html><meta charset="utf-8"><title>Coacher — this week</title>
<style>
body{{font:14px/1.6 -apple-system,Segoe UI,Roboto,sans-serif;color:#0f172a;max-width:760px;margin:2rem auto;padding:0 1rem}}
h1{{font-size:20px;font-weight:600;margin:0}} .head{{display:flex;justify-content:space-between;align-items:baseline}}
.muted{{color:#94a3b8;font-size:13px}} .lbl{{font-size:13px;font-weight:600;color:#475569;margin:1.4rem 0 .5rem}}
.alert{{display:flex;align-items:center;gap:.75rem;background:#fff;border:1px solid #e2e8f0;border-left:3px solid;border-radius:0 10px 10px 0;padding:.6rem .9rem;margin-bottom:.5rem}}
.pill{{font-size:11px;font-weight:600;text-transform:uppercase;letter-spacing:.03em}} .who{{flex:1}} .sub{{color:#94a3b8}}
.num{{font-weight:600;width:64px;text-align:right}} .act{{color:#475569;font-size:13px;width:230px}}
table{{width:100%;border-collapse:collapse}} th{{text-align:left;color:#94a3b8;font-weight:400;font-size:12px;padding:.4rem .6rem}}
td{{padding:.5rem .6rem;border-top:1px solid #e2e8f0}} .r{{text-align:right}}
</style>
<div class="head"><h1>Coacher — this week</h1><div class="muted">generated {now} · ads-attributed net</div></div>
<div class="lbl">Needs your attention</div>{esc_rows}
<div class="lbl">This week's plan</div>
<table><tr><th>product</th><th>purposes</th><th class="r">cells</th><th class="r">planned spend</th><th class="r">expected net</th></tr>{plan_rows}</table>
<p class="muted">Source: V_PLAN_ESCALATION + DE_WEEKLY_PLAN (live). Regenerated each refresh.</p>
"""
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(doc)
    print(f"wrote {OUT}")

if __name__ == "__main__":
    main()

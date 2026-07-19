import { useState } from 'react';

// Coach logic as a flow chart — the whole decision tree, hidden by default. A toggle per STRATEGY
// (Exact Boost / Intent / Competitors / Brand Defense / Product Defense / Auto) swaps the strategy-
// specific "profitable" bar on the shared coacher skeleton. New campaigns (≤20d) run a separate launch
// controller, shown as the left track. Bars mirror DE_COACH_THRESHOLDS.PROFITABLE_ROAS (GUARDIAN).

type Strat = { key: string; label: string; bar: number; note?: string };
const STRATS: Strat[] = [
  { key: 'EXACT_BOOST', label: 'Exact Boost', bar: 1.1 },
  { key: 'INTENT', label: 'Intent', bar: 1.1, note: '≈0.7× once organic halo is counted' },
  { key: 'COMPETITOR', label: 'Competitors', bar: 1.1, note: 'accept lower if SQP share is growing' },
  { key: 'BRAND_DEFENSE', label: 'Brand Defense', bar: 3.0, note: 'own the brand SERP — below 3× underperforms' },
  { key: 'PRODUCT_DEFENSE', label: 'Product Defense', bar: 2.0, note: 'high-intent clicks must convert' },
  { key: 'AUTO', label: 'Auto', bar: 1.1 },
];

function Box({ title, color, children }: { title: string; color: string; children: React.ReactNode }) {
  return (
    <div className={`rounded-md border px-2.5 py-1.5 ${color}`}>
      <div className="text-label font-medium mb-0.5">{title}</div>
      <ul className="text-label text-subtle list-disc pl-3.5 leading-snug flex flex-col gap-0.5">{children}</ul>
    </div>
  );
}
const Arrow = () => <div className="text-faint text-center text-label leading-none my-0.5">↓</div>;

export function CoachFlowchart() {
  const [open, setOpen] = useState(false);
  const [sel, setSel] = useState('EXACT_BOOST');
  const s = STRATS.find(x => x.key === sel)!;

  return (
    <div className="mb-3 rounded-md border border-border bg-surface/30 px-3 py-2">
      <button onClick={() => setOpen(o => !o)} className="text-label flex items-center gap-1">
        <span className="text-faint">{open ? '▾' : '▸'}</span>
        <span className="font-medium text-amber-400">Coach logic</span>
        <span className="text-faint">— full decision flow{open ? '' : ' (click to expand)'}</span>
      </button>

      {open && (
        <div className="mt-2">
          {/* strategy toggle */}
          <div className="flex items-center flex-wrap gap-1 mb-2">
            <span className="text-label text-faint mr-1">Strategy:</span>
            {STRATS.map(x => (
              <button key={x.key} onClick={() => setSel(x.key)}
                className={`text-label px-2 py-0.5 rounded border ${sel === x.key ? 'border-amber-500/50 text-amber-300 bg-amber-500/10' : 'border-border text-muted hover:bg-white/5'}`}>
                {x.label}
              </button>
            ))}
            <span className="text-label text-faint ml-2">profitable bar: <span className="text-emerald-400 font-mono">≥ {s.bar.toFixed(1)}×</span>{s.note ? <span className="text-faint"> · {s.note}</span> : null}</span>
          </div>

          {/* age split */}
          <div className="rounded-md border border-border px-2.5 py-1 text-label text-center mb-1">
            <span className="text-muted">Campaign age?</span>
          </div>
          <div className="grid grid-cols-2 gap-3">
            {/* NEW track */}
            <div>
              <div className="text-label text-violet-300 mb-1">≤ 20 days → <span className="font-medium">Launch controller</span> <span className="text-faint">(own engine, ignores the 7/28d rules)</span></div>
              <Box title="Bid — last-day vs prior-2-day" color="border-violet-500/30 bg-violet-500/5">
                <li>Cut ×0.8 only if <b>both</b> last-day &lt; 0.9× <b>and</b> prior-2-day &lt; 0.9× (floor $0.30)</li>
                <li>Raise ×1.3 if prior-2-day &gt; 1.5× (strong); ×1.15 if last-day &gt; 1.2× (weak) — ceiling $1.50</li>
                <li>Starving (spend ≤ 60% budget) → ×1.10 to buy traffic</li>
              </Box>
              <Arrow />
              <Box title="Budget — dark % gate" color="border-violet-500/30 bg-violet-500/5">
                <li>Out of budget &gt; 10% of day + prior-2-day &gt; 1.5× → raise to a full day (÷ %active), cap ×3</li>
                <li>…or last-day &gt; 1.2× → cap ×2</li>
                <li>Not maxing → hold; genuinely losing → trim toward the $10 floor</li>
              </Box>
              <Arrow />
              <Box title="Negate" color="border-violet-500/30 bg-violet-500/5">
                <li>Search term with 15 clicks / 0 orders → negative exact (keyword stays alive)</li>
              </Box>
            </div>

            {/* MATURE track */}
            <div>
              <div className="text-label text-amber-300 mb-1">&gt; 20 days → <span className="font-medium">Coacher (Guardian)</span></div>
              <Box title="Data gate" color="border-border bg-surface/40">
                <li>Judge a keyword only at ≥ 15 clicks / 12 months (proven seasonal held for its season)</li>
              </Box>
              <Arrow />
              <Box title="Bid — 7d direction, 28d confirm" color="border-amber-500/30 bg-amber-500/5">
                <li>Moderate signals need 7d &amp; 28d to agree; an extreme week acts alone</li>
                <li>Profitable ≥ <span className="text-emerald-400 font-mono">{s.bar.toFixed(1)}×</span> (this strategy). A proven 28d winner (≥ 1.5×) is never cut on one weak week; a cut defers while the last 3 days improve</li>
                <li>Sweet spot: still ≥ 2× at its band → bid past it toward the $2 cap; slips &lt; 1.5× → eased back. 1 change / kw / 7 days</li>
              </Box>
              <Arrow />
              <Box title="Budget — engine net ROAS" color="border-amber-500/30 bg-amber-500/5">
                <li>Cut if &lt; 0.9× (needs ≥ $25 spend/8w); raise if ≥ 1.1× <b>and</b> using ≥ 90% of budget (7d). 1 change / 3 days</li>
              </Box>
              <Arrow />
              <Box title="Negate" color="border-amber-500/30 bg-amber-500/5">
                <li>0 orders on ≥ 15 clicks (8w), still clicking last 5 days → negative exact</li>
                <li>Peak converter → ⚠ keep (seasonal); wrong-colour term → “+ hero” instead of blocking</li>
              </Box>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

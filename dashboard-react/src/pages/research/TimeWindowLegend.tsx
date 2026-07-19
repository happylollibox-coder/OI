/** Time-window legend for the Research page.
 *
 *  The page deliberately does NOT have one window — each panel measures over the span that
 *  makes sense for it (a seasonal intent can only be judged on its own season; market demand
 *  needs 2y). That's fine, but it MUST be visible: the same "1.5x" means different things
 *  over 90 days and over all time.
 *
 *  ⚠️ The segment badges genuinely have NO date filter (/api/research/segment-reasoning and
 *  /api/research/segment-terms carry no date predicate), so they average every day of history.
 *  Flagged rather than quietly re-scoped — changing it would move numbers Ori reads daily.
 */
const WINDOWS: { label: string; window: string; warn?: boolean; hint: string }[] = [
  {
    label: 'Segments',
    window: 'all time',
    warn: true,
    hint: 'The Gender/Age/Occasion/Product-Type badges + their search-term popup have NO date filter — they average all history, including years-old data.',
  },
  {
    label: 'Market data',
    window: '104w',
    hint: 'rank · fit · demand — FACT_RESEARCH_RANKED / V_RESEARCH_TERMS aggregate a 104-week (2 year) market window.',
  },
  {
    label: 'Intents',
    window: '90d · seasonal = last season',
    hint: 'Ads money per intent: generic = last 90 days; seasonal = that holiday’s last started season (e.g. Easter 2026-02-16 → 2026-04-10), because a 90d read is meaningless out of season.',
  },
  {
    label: 'Product targets',
    window: '180d',
    hint: 'Product-Targeting Opportunities (ASIN targeting CVR) uses a 180-day window.',
  },
  {
    label: 'Keyword recs',
    window: '104w',
    hint: 'Cluster / coverage explain popups reconstruct over the same 104-week research window.',
  },
];

export function TimeWindowLegend() {
  return (
    <div className="mb-3 flex flex-wrap items-center gap-x-2 gap-y-1 text-[9px] text-faint">
      <span className="uppercase tracking-wide">Time windows</span>
      {WINDOWS.map(w => (
        <span
          key={w.label}
          title={w.hint}
          className={`px-1.5 py-0.5 rounded border cursor-help ${
            w.warn
              ? 'border-amber-500/40 bg-amber-500/10 text-amber-400'
              : 'border-border/30 bg-white/[0.02] text-muted'
          }`}
        >
          {w.warn && '⚠ '}
          <span className="text-subtle">{w.label}</span> {w.window}
        </span>
      ))}
      <span className="text-faint italic">no single page window — hover each</span>
    </div>
  );
}

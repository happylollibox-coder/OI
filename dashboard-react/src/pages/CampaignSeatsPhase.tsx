import { useEffect, useRef, useState } from 'react';
import { cubeLoadWithMeta } from '../hooks/useCubeData';

// CAMPAIGN SEATS — the Brain's seat entitlement, per campaign (Ori, 2026-08-25).
// ALLOWANCE IS EARNED, NOT GRANTED. A campaign clearing its family bar earns an allowance of 20%
// of its daily budget and spends it on UNPROFITABLE keywords at one seat per $7. A campaign under
// its bar earns no allowance at all and gets exactly ONE seat, aimed at its MOST PROFITABLE
// keyword, with the bid free to move either way toward the campaign's break-even — mend before you
// grow. That inversion is the new part: every seat in the plan before this went to a losing
// keyword, so there was no way to repair a campaign by leaning on the thing that already works.
// Display-only. The view decides nothing and this panel queues nothing.
// Source: V_CAMPAIGN_SEAT_PLAN. Doctrine: architecture/FAMILY_SEAT_REGISTER.md.

type Row = {
  campaignId: string;
  campaignName: string;
  family: string;
  purpose: string;
  budget: number | null;
  allowance: number | null;
  seats: number | null;
  roas: number | null;
  bar: number | null;
  repairText: string | null;
  repairBid: number | null;
  repairTarget: number | null;
  repairAffordable: number | null;
  repairOrders: number | null;
  repairDir: string | null;
  repairCapped: boolean;
  sentence: string;
};

const num = (v: unknown): number | null =>
  v === null || v === undefined || v === '' ? null : Number(v);

function money(v: number | null, dp = 2): string {
  return v === null || Number.isNaN(v) ? '—' : `$${v.toFixed(dp)}`;
}

function toRow(r: Record<string, unknown>): Row {
  return {
    campaignId: String(r['CampaignSeatPlan.campaignId'] ?? ''),
    campaignName: String(r['CampaignSeatPlan.campaignName'] ?? ''),
    family: String(r['CampaignSeatPlan.family'] ?? ''),
    purpose: String(r['CampaignSeatPlan.seatPurpose'] ?? ''),
    budget: num(r['CampaignSeatPlan.budget']),
    allowance: num(r['CampaignSeatPlan.allowance']),
    seats: num(r['CampaignSeatPlan.seats']),
    roas: num(r['CampaignSeatPlan.adsNetRoas']),
    bar: num(r['CampaignSeatPlan.bar']),
    repairText: (r['CampaignSeatPlan.repairTargetText'] as string) ?? null,
    repairBid: num(r['CampaignSeatPlan.repairCurrentBid']),
    repairTarget: num(r['CampaignSeatPlan.repairTargetCpc']),
    repairAffordable: num(r['CampaignSeatPlan.repairAffordableCpc']),
    repairOrders: num(r['CampaignSeatPlan.repairEvidenceOrders']),
    repairDir: (r['CampaignSeatPlan.repairDirection'] as string) ?? null,
    repairCapped: r['CampaignSeatPlan.repairTargetCapped'] === true
      || r['CampaignSeatPlan.repairTargetCapped'] === 'true',
    sentence: String(r['CampaignSeatPlan.sentence'] ?? ''),
  };
}

// ROAS against the bar, which is the test that decides whether allowance is earned at all.
function BarCell({ r }: { r: Row }) {
  const clears = r.roas !== null && r.bar !== null && r.roas >= r.bar;
  return (
    <td className="px-2 py-1 tabular-nums whitespace-nowrap">
      <span className={clears ? 'text-emerald-300' : 'text-amber-300'}>
        {r.roas === null ? '—' : r.roas.toFixed(2)}
      </span>
      <span className="text-faint"> vs {r.bar === null ? '—' : r.bar.toFixed(2)}</span>
    </td>
  );
}

export function CampaignSeatsPhase({ defaultOpen }: { defaultOpen?: boolean }) {
  // Explicit close is final — the same rule every other phase follows (Ori 2026-08-17).
  const [openState, setOpenState] = useState<boolean | null>(null);
  const open = openState ?? defaultOpen ?? false;
  const [rows, setRows] = useState<Row[] | null>(null);
  const [failed, setFailed] = useState(false);

  // LAZY: the section earns its query on the first expand (WEEKLY_RUN_UX.md).
  const fetchedRef = useRef(false);
  useEffect(() => {
    if (!open || fetchedRef.current) return;
    fetchedRef.current = true;
    let alive = true;
    cubeLoadWithMeta({
      dimensions: [
        'CampaignSeatPlan.campaignId', 'CampaignSeatPlan.campaignName', 'CampaignSeatPlan.family',
        'CampaignSeatPlan.seatPurpose', 'CampaignSeatPlan.budget', 'CampaignSeatPlan.allowance',
        'CampaignSeatPlan.seats', 'CampaignSeatPlan.adsNetRoas', 'CampaignSeatPlan.bar',
        'CampaignSeatPlan.repairTargetText', 'CampaignSeatPlan.repairCurrentBid',
        'CampaignSeatPlan.repairTargetCpc', 'CampaignSeatPlan.repairAffordableCpc',
        'CampaignSeatPlan.repairEvidenceOrders', 'CampaignSeatPlan.repairDirection',
        'CampaignSeatPlan.repairTargetCapped', 'CampaignSeatPlan.sentence',
      ],
    }).then(res => {
      if (!alive) return;
      // A stale or failed cube returns {data: [], error}. Rendering the empty state here would
      // claim there is nothing to show, which is a lie — the same trap caught in RevivalsPhase.
      if (res.error) { setFailed(true); return; }
      setRows((res.data as Record<string, unknown>[]).map(toRow));
    }).catch(() => { if (alive) setFailed(true); });
    return () => { alive = false; };
  }, [open]);

  const repair = (rows ?? []).filter(r => r.purpose === 'REPAIR')
    .sort((a, b) => (b.budget ?? 0) - (a.budget ?? 0));
  const experiment = (rows ?? []).filter(r => r.purpose === 'EXPERIMENT')
    .sort((a, b) => (b.seats ?? 0) - (a.seats ?? 0) || (b.budget ?? 0) - (a.budget ?? 0));
  const unmeasured = (rows ?? []).filter(r => r.purpose === 'UNMEASURED');
  const seatsTotal = (rows ?? []).reduce((s, r) => s + (r.seats ?? 0), 0);
  const allowanceTotal = (rows ?? []).reduce((s, r) => s + (r.allowance ?? 0), 0);

  const headline = failed
    ? '— could not load'
    : !rows
      ? (open || fetchedRef.current) ? '— loading…' : '— expand to load'
      : `— ${seatsTotal} seats · ${repair.length} campaigns mending on 1 seat · `
        + `${experiment.length} earning ${money(allowanceTotal, 0)}/day of allowance`;

  return (
    <div className="mb-3 rounded-md border border-border bg-surface/30 px-3 py-2">
      <div className="flex items-center gap-1">
        <button className="text-label flex items-center gap-1 flex-1 min-w-0"
                onClick={() => setOpenState(!open)}>
          <span className="text-faint">{open ? '▾' : '▸'}</span>
          <span className="font-medium text-emerald-300">Campaign seats</span>
          <span className="text-faint truncate">
            {headline}
            {' '}· allowance is earned: clear the bar and 20% of budget buys seats at $7 · display-only
          </span>
        </button>
      </div>

      {open && rows && (
        <div className="mt-2 space-y-3">
          {/* MEND BEFORE YOU GROW. One seat, aimed at the best keyword, price free to move either way. */}
          {repair.length > 0 && (
            <div>
              <div className="text-label text-faint mb-1">
                Under the bar — no allowance, one seat each on the campaign&apos;s best keyword
              </div>
              <table className="w-full text-label">
                <thead className="text-faint">
                  <tr className="text-left">
                    <th className="px-2 py-1">campaign</th>
                    <th className="px-2 py-1">budget</th>
                    <th className="px-2 py-1">ROAS vs bar</th>
                    <th className="px-2 py-1">lean on</th>
                    <th className="px-2 py-1">bid</th>
                    <th className="px-2 py-1">evidence</th>
                  </tr>
                </thead>
                <tbody>
                  {repair.map(r => (
                    <tr key={r.campaignId} className="border-t border-border/40" title={r.sentence}>
                      <td className="px-2 py-1 truncate max-w-[16rem]">
                        {r.campaignName}
                        <span className="text-faint text-label"> · {r.family}</span>
                      </td>
                      <td className="px-2 py-1 tabular-nums">{money(r.budget, 0)}</td>
                      <BarCell r={r} />
                      <td className="px-2 py-1 truncate max-w-[14rem]">{r.repairText ?? '—'}</td>
                      <td className="px-2 py-1 tabular-nums whitespace-nowrap">
                        {money(r.repairBid)}
                        <span className="text-faint"> → </span>
                        <span className={r.repairDir === 'RAISE' ? 'text-emerald-300' : 'text-amber-300'}>
                          {money(r.repairTarget)}
                        </span>
                        {/* A capped target is a DIFFERENT claim from a measured one and must say so:
                            the affordable price sat outside half-to-double the current bid, usually
                            because it rests on one or two orders. */}
                        {r.repairCapped && (
                          <span className="text-faint" title={`affordable ${money(r.repairAffordable)} — bounded to half-to-double the current bid`}>
                            {' '}(capped)
                          </span>
                        )}
                      </td>
                      <td className="px-2 py-1 tabular-nums">
                        <span className={(r.repairOrders ?? 0) < 3 ? 'text-amber-300' : ''}>
                          {r.repairOrders ?? 0} orders
                        </span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}

          {/* Earned allowance: 20% of budget, one seat per $7, spent on keywords being repaired. */}
          {experiment.length > 0 && (
            <div>
              <div className="text-label text-faint mb-1">
                Clearing the bar — 20% of budget as allowance, one seat per $7
              </div>
              <table className="w-full text-label">
                <thead className="text-faint">
                  <tr className="text-left">
                    <th className="px-2 py-1">campaign</th>
                    <th className="px-2 py-1">budget</th>
                    <th className="px-2 py-1">ROAS vs bar</th>
                    <th className="px-2 py-1">allowance</th>
                    <th className="px-2 py-1">seats</th>
                  </tr>
                </thead>
                <tbody>
                  {experiment.map(r => (
                    <tr key={r.campaignId} className="border-t border-border/40" title={r.sentence}>
                      <td className="px-2 py-1 truncate max-w-[16rem]">
                        {r.campaignName}
                        <span className="text-faint text-label"> · {r.family}</span>
                      </td>
                      <td className="px-2 py-1 tabular-nums">{money(r.budget, 0)}</td>
                      <BarCell r={r} />
                      <td className="px-2 py-1 tabular-nums">{money(r.allowance)}</td>
                      <td className="px-2 py-1 tabular-nums">
                        {/* Zero is a real answer: profitable, but too small to afford a $7 seat.
                            It is working and cannot experiment safely — leave it alone. */}
                        <span className={(r.seats ?? 0) === 0 ? 'text-faint' : ''}>
                          {r.seats ?? 0}
                          {(r.seats ?? 0) === 0 && ' — too small to seat'}
                        </span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}

          {unmeasured.length > 0 && (
            <div className="text-label text-faint">
              {unmeasured.length} campaign(s) spent nothing in the settled window — not judged, no seat.
              Unmeasured never reads as bad.
            </div>
          )}
        </div>
      )}
    </div>
  );
}

export default CampaignSeatsPhase;

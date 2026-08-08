// Advisory FBA/AWD split panel. Reads the engine (`fbaAwdSplit.ts`), shows the
// operator what to ship where — and, in the calculation ledger, every input the
// recommendation was built from, including the shipments that were EXCLUDED and
// why, and the ones Amazon's own inventory snapshot cut down to size.
// Nothing here writes: no BigQuery rows, no bulksheet, no automation.
//
// Layout only. Arithmetic, partitioning and reconciliation live in
// `splitPanelData.ts`; the split itself lives in `fbaAwdSplit.ts`.
import { useMemo, useState } from 'react';
import {
  planSplit, plannedWalkWindow, methodCaption,
  type AwdMethod, type FbaMethod, type SplitLeg, type TransferRow,
} from '../fbaAwdSplit';
import { splitChartWindow, reduceSeriesToWeeks } from '../splitChart';
import { SplitSimulationChart } from './SplitSimulationChart';
import { useShipmentConstants } from '../hooks/useShipmentConstants';
import type { ProjectionShipment } from '../stockProjection';
import type { ForecastDemandMap, ForecastMetaMap, MonthSeasonMap } from '../planTypes';
import {
  FBA_TARGET_DOC, FBA_REORDER_DOC, FBA_BATCH_DOC, TOTAL_TARGET_DOC,
  OFFERED_FBA_METHODS, OFFERED_AWD_METHODS, docLabel, resolveBatchInput,
  narrowTransitDays, partitionShipmentsForLedger, transitLedgerEntries, statusCaption,
  groupProductsByFamily, resolveFamilySelection,
  reconcileInboundWithSnapshot, dispositionNote, awdInboundFromSnapshot,
  buildDemandCurve, buildDemandLedger,
  type LedgerShipment, type InboundDisposition, type ReconciledInboundRow,
} from '../splitPanelData';
import { fmt } from '../utils';

export interface FbaAwdSplitPanelProps {
  products: Array<{ product: string; packageQuantity: number }>;
  fbaMap: Record<string, number>;
  awdMap: Record<string, number>;
  mfrReadyMap: Record<string, number>;
  /**
   * Amazon's own count of stock on the water, per product. Absent means the
   * figure is unavailable — which is NOT the same as zero, and the
   * reconciliation says so rather than deleting every inbound shipment.
   */
  inTransitFbaMap?: Record<string, number>;
  inTransitAwdMap?: Record<string, number>;
  shipmentsByProduct: Record<string, ProjectionShipment[]>;
  demandMap: ForecastDemandMap;
  seasonMap: MonthSeasonMap;
  metaMap: ForecastMetaMap;
  growthOverrides?: Record<string, number>;
  snapshotDate: string | null;
  inventoryError?: string | null;
  /** Injectable so a test can pin the plan; defaults to now. */
  today?: Date;
}

// ─── Shared bits of the Plan-page idiom ─────────────────────

const CARD = 'rounded-lg border border-border/20 bg-surface/30 px-4 py-3';
const LABEL = 'text-[9px] font-bold text-muted/60 uppercase tracking-wider';
const TH = 'text-left font-bold text-muted/60 text-[9px] uppercase tracking-wider py-1 pr-3';
const TD = 'py-1 pr-3 font-mono text-[10px] text-[color:var(--color-text)]';
const INPUT = 'bg-surface border border-border/40 rounded px-2 py-1 text-[11px] text-[color:var(--color-text)]';

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className={`${CARD} mb-2`}>
      <div className={`${LABEL} mb-2`}>{title}</div>
      {children}
    </div>
  );
}

/** One ledger line: what it is, what it was, where it came from. */
function KV({ label, value, source }: { label: string; value: React.ReactNode; source: string }) {
  return (
    <div className="flex items-baseline gap-2 py-0.5">
      <span className="text-[10px] text-muted flex-1 min-w-0">{label}</span>
      <span className="font-mono text-[11px] text-[color:var(--color-text)]">{value}</span>
      <span className="text-[8px] text-subtle uppercase tracking-wider w-[130px] text-right shrink-0">{source}</span>
    </div>
  );
}

function Notice({ text, tone }: { text: string; tone: 'warning' | 'negative' }) {
  const color = tone === 'negative' ? 'var(--color-negative)' : 'var(--color-warning)';
  return (
    <div className="flex items-start gap-2 text-[10px] leading-snug py-1 px-2 rounded border mb-1"
      style={{ color, borderColor: color, background: 'var(--color-surface)' }}>
      <span aria-hidden="true">⚠</span><span>{text}</span>
    </div>
  );
}

// ─── Ledger sub-tables ──────────────────────────────────────

function ShipmentLedgerTable({ rows, greyed }: { rows: LedgerShipment[]; greyed: boolean }) {
  if (!rows.length) {
    return <div className="text-[10px] text-subtle italic">None.</div>;
  }
  return (
    <table className="w-full" style={greyed ? { opacity: 0.55 } : undefined}>
      <thead>
        <tr>
          <th className={TH}>Arrival</th><th className={TH}>Units</th>
          <th className={TH}>Dest</th><th className={TH}>Status</th>
          <th className={TH}>{greyed ? 'Why it was left out' : 'Effect'}</th>
        </tr>
      </thead>
      <tbody>
        {rows.map((r, i) => (
          <tr key={`${r.arrivalDate}-${r.status}-${i}`} className="border-t border-border/10">
            <td className={TD}>{r.arrivalDate || '—'}</td>
            <td className={TD}>{fmt(r.qty)}</td>
            <td className={TD}>{r.destination}</td>
            <td className={TD}>{statusCaption(r.status)}</td>
            <td className="py-1 text-[10px] text-muted">
              {r.exclusionReason ?? `Adds ${fmt(r.qty)} units to FBA on ${r.arrivalDate}`}
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

/**
 * A trimmed or dropped row must not read like an excluded one: the shipment is
 * confirmed, FBA-bound and in-window, and it is Amazon's count that overrode
 * it. Colour plus an explicit badge, on its own table.
 */
const DISPOSITION_BADGE: Record<InboundDisposition, { label: string; color: string }> = {
  KEPT: { label: 'Kept', color: 'var(--color-text)' },
  TRIMMED: { label: 'Trimmed', color: 'var(--color-warning)' },
  DROPPED: { label: 'Dropped', color: 'var(--color-negative)' },
};

function ReconciledLedgerTable({ rows }: { rows: ReconciledInboundRow[] }) {
  if (!rows.length) {
    return <div className="text-[10px] text-subtle italic">None.</div>;
  }
  return (
    <table className="w-full">
      <thead>
        <tr>
          <th className={TH}>Arrival</th><th className={TH}>Records say</th><th className={TH}>Counted</th>
          <th className={TH}>Dest</th><th className={TH}>Status</th>
          <th className={TH}>Verdict</th><th className={TH}>Effect</th>
        </tr>
      </thead>
      <tbody>
        {rows.map((r, i) => {
          const badge = DISPOSITION_BADGE[r.disposition];
          return (
            <tr key={`${r.row.arrivalDate}-${r.row.status}-${i}`} className="border-t border-border/10"
              style={r.disposition === 'DROPPED' ? { opacity: 0.6 } : undefined}>
              <td className={TD}>{r.row.arrivalDate || '—'}</td>
              <td className={TD}>{fmt(r.recordUnits)}</td>
              <td className={TD} style={{ color: badge.color }}>{fmt(r.countedUnits)}</td>
              <td className={TD}>{r.row.destination}</td>
              <td className={TD}>{statusCaption(r.row.status)}</td>
              <td className="py-1 pr-3 text-[10px] font-bold" style={{ color: badge.color }}>{badge.label}</td>
              <td className="py-1 text-[10px] text-muted">{dispositionNote(r)}</td>
            </tr>
          );
        })}
      </tbody>
    </table>
  );
}

function DemandLedgerTable({ rows }: { rows: ReturnType<typeof buildDemandLedger> }) {
  return (
    <table className="w-full">
      <thead>
        <tr>
          <th className={TH}>Month</th><th className={TH}>Forecast</th><th className={TH}>Growth</th>
          <th className={TH}>Units used</th><th className={TH}>Peak days</th>
          <th className={TH}>Off / peak per day</th><th className={TH}>Holiday</th>
        </tr>
      </thead>
      <tbody>
        {rows.map(r => (
          <tr key={r.yearMonth} className="border-t border-border/10">
            <td className={TD}>{r.label}</td>
            <td className={TD}>{fmt(r.forecastUnits)}</td>
            <td className={TD}>×{fmt(r.growth, 2)}</td>
            <td className={TD}>{fmt(r.units)}</td>
            <td className={TD}>{r.peakDays} of {r.daysInMonth}</td>
            <td className={TD}>{fmt(r.offseasonDailyUnits, 1)} / {fmt(r.peakDailyUnits, 1)}</td>
            <td className="py-1 pr-3 text-[10px] text-muted">{r.holidays ?? '—'}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

// ─── Decision rows ──────────────────────────────────────────

function LegCard({ leg }: { leg: SplitLeg }) {
  return (
    <div className="rounded border border-border/20 bg-surface/20 px-3 py-2 mb-2">
      <div className="flex flex-wrap items-baseline gap-x-4 gap-y-1">
        <span className="text-[11px] font-bold text-[color:var(--color-text)]">
          → {leg.destination}
        </span>
        <span className="font-mono text-[13px] text-[color:var(--color-text)]">{fmt(leg.units)} units</span>
        <span className="font-mono text-[11px] text-muted">{fmt(leg.cartons)} cartons</span>
        <span className="text-[10px] text-muted">{methodCaption(leg.method)}</span>
        <span className="font-mono text-[10px] text-muted">{leg.transitDays}d transit</span>
      </div>
      <div className="flex flex-wrap gap-x-5 gap-y-1 mt-1.5">
        {([['Ship', leg.shipDate], ['Arrives', leg.arrivalDate], ['Sellable', leg.sellableDate]] as const).map(([k, v]) => (
          <span key={k} className="text-[10px] text-muted">
            {k} <span className="font-mono text-[color:var(--color-text)]">{v}</span>
          </span>
        ))}
      </div>
      <div className="text-[10px] text-subtle leading-snug mt-1.5">{leg.reason}</div>
    </div>
  );
}

function TransferTable({ rows }: { rows: TransferRow[] }) {
  if (!rows.length) {
    return <div className="text-[10px] text-subtle italic">No AWD → FBA transfers needed inside the horizon.</div>;
  }
  return (
    <table className="w-full">
      <thead>
        <tr>
          <th className={TH}>Order on</th><th className={TH}>Arrives</th><th className={TH}>Units</th>
          <th className={TH}>Cartons</th><th className={TH}>Cover before</th><th className={TH}>Cover after</th>
        </tr>
      </thead>
      <tbody>
        {rows.map(t => (
          <tr key={`${t.orderDate}-${t.arrivalDate}`} className="border-t border-border/10">
            <td className={TD}>{t.orderDate}</td>
            <td className={TD}>{t.arrivalDate}</td>
            <td className={TD}>{fmt(t.units)}</td>
            <td className={TD}>{fmt(t.cartons)}</td>
            <td className={TD}>{docLabel(t.docBefore)}</td>
            <td className={TD}>{docLabel(t.docAfter)}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

// ─── Panel ──────────────────────────────────────────────────

export function FbaAwdSplitPanel(props: FbaAwdSplitPanelProps) {
  const { products, fbaMap, awdMap, mfrReadyMap, shipmentsByProduct, snapshotDate, inventoryError } = props;

  const [selectedFamily, setSelectedFamily] = useState('');
  const [selected, setSelected] = useState('');
  const [entered, setEntered] = useState<{ product: string; value: string } | null>(null);
  const [methodChoice, setMethodChoice] = useState<'AUTO' | FbaMethod>('AUTO');
  // The AWD leg has no auto pick to fall back to — there is nothing to escalate
  // against, since the reserve is not what runs out — so the default IS a route.
  const [awdMethodChoice, setAwdMethodChoice] = useState<AwdMethod>(OFFERED_AWD_METHODS[0]);
  // How full a direct delivery leaves FBA. 60 avoids paying transfer handling
  // almost immediately; 45 keeps less stock in the expensive warehouse. Which
  // wins depends on how long the units would otherwise sit at AWD and whether
  // that stretch falls in Q4 — so it is the operator's call, not a constant.
  const [batchDoc, setBatchDoc] = useState<number>(FBA_BATCH_DOC);
  const reserveDoc = TOTAL_TARGET_DOC - batchDoc;

  const constants = useShipmentConstants();
  const narrowing = useMemo(() => narrowTransitDays(constants.transitDays), [constants.transitDays]);
  const today = useMemo(() => props.today ?? new Date(), [props.today]);

  // Family first, then product within it — 30+ products across four families is
  // a scroll hunt otherwise, and the family is how a batch is thought about.
  const grouping = useMemo(
    () => groupProductsByFamily(products, p => props.metaMap[p]?.family),
    [products, props.metaMap]);
  // Both selections fall back rather than going stale when the list changes.
  const { family, product } = resolveFamilySelection(grouping, selectedFamily, selected);
  const familyProducts = grouping.byFamily[family] ?? [];
  // Switching product drops back to that product's own prefill, never carrying the last one over.
  const typed = entered && entered.product === product ? entered.value : '';
  const batch = useMemo(
    () => resolveBatchInput({ product, products, mfrReadyMap, typed }),
    [product, products, mfrReadyMap, typed]);
  const { packageQuantity, readyUnits, prefillCartons, cartons, batchUnits, isDefaulted } = batch;

  const shipments = useMemo(() => shipmentsByProduct[product] ?? [], [shipmentsByProduct, product]);
  const curve = useMemo(() => buildDemandCurve({
    product, demandMap: props.demandMap, seasonMap: props.seasonMap,
    metaMap: props.metaMap, growthOverrides: props.growthOverrides,
  }), [product, props.demandMap, props.seasonMap, props.metaMap, props.growthOverrides]);

  // The window the engine will walk, stated by the engine itself before the
  // plan exists — the ledger has to partition shipments in order to decide what
  // the engine is given, so it cannot wait for `plan.walkWindow`.
  const plannedWindow = useMemo(() => plannedWalkWindow(today, TOTAL_TARGET_DOC), [today]);
  const shipLedger = useMemo(() => partitionShipmentsForLedger(shipments, plannedWindow), [shipments, plannedWindow]);

  // Amazon's snapshot is the authority on how much is inbound; the records are
  // the authority on when. Reconcile before planning, never after.
  const snapshotInboundFba = props.inTransitFbaMap?.[product];
  const snapshotInboundAwd = props.inTransitAwdMap?.[product];
  const reconciliation = useMemo(
    () => reconcileInboundWithSnapshot(shipLedger.counted, snapshotInboundFba),
    [shipLedger, snapshotInboundFba]);
  const awdInbound = useMemo(() => awdInboundFromSnapshot(snapshotInboundAwd), [snapshotInboundAwd]);

  // planSplit walks 465 days, so it is memoized on exactly what it reads.
  const plan = useMemo(() => {
    if (!product || !narrowing.ok) return null;
    return planSplit({
      cartons: batch.cartons, packageQuantity: batch.packageQuantity,
      fbaOnHand: fbaMap[product] ?? 0,
      awdOnHand: awdMap[product] ?? 0,
      awdInbound,
      shipments: reconciliation.shipments, curve,
      transitDays: narrowing.transitDays,
      fbaInboundBufferDays: constants.fbaInboundBufferDays,
      today, fbaTargetDoc: FBA_TARGET_DOC, fbaReorderDoc: FBA_REORDER_DOC,
      fbaBatchDoc: batchDoc, totalTargetDoc: TOTAL_TARGET_DOC,
      methodOverride: methodChoice === 'AUTO' ? undefined : methodChoice,
      awdMethodOverride: awdMethodChoice,
    });
  }, [product, narrowing, batch, fbaMap, awdMap, awdInbound, reconciliation, curve,
    constants.fbaInboundBufferDays, today, methodChoice, awdMethodChoice, batchDoc]);

  // The window follows the COMBINED target — it is about seeing the whole
  // position land, and most of the batch is still at sea at 45 days.
  const chartRows = useMemo(
    () => (plan?.ok ? reduceSeriesToWeeks(plan.series, splitChartWindow(today, TOTAL_TARGET_DOC)) : []),
    [plan, today]);
  // The engine states its own window at plan time; the panel must not re-derive
  // it from `plan.series`, or trimming that series for display would silently
  // start labelling in-window arrivals as beyond-horizon.
  const walk = plan?.ok ? plan.walkWindow : null;
  const demandRows = useMemo(() => walk ? buildDemandLedger(curve, walk.from, walk.to) : [], [walk, curve]);

  if (!products.length) {
    return (
      <div className={CARD}>
        <div className={LABEL}>FBA / AWD Split</div>
        <div className="text-[11px] text-muted mt-2">No products to plan — this panel needs at least one product with a package quantity.</div>
      </div>
    );
  }

  return (
    <div className={CARD}>
      {/* Four levels, on two lines. One sentence carrying four numbers reads as
          a list of quantities; split by what each governs, it reads as a rule:
          what a delivery does, then what the ongoing transfers do. */}
      <div className="flex items-baseline justify-between gap-4 mb-3">
        <div className={LABEL}>FBA / AWD Split — advisory, nothing is sent</div>
        <div className="text-[9px] text-subtle text-right leading-relaxed">
          <div>This delivery fills FBA to {batchDoc} days</div>
          <div>
            Then transfers order at {FBA_REORDER_DOC}, restore to {FBA_TARGET_DOC} · {TOTAL_TARGET_DOC} days FBA + AWD combined
          </div>
        </div>
      </div>

      {/* ── Inputs ── */}
      <div className="flex flex-wrap items-end gap-4 mb-3">
        <label className="flex flex-col gap-1">
          <span className={LABEL}>Family</span>
          <select
            className={INPUT} value={family}
            onChange={e => { setSelectedFamily(e.target.value); setSelected(''); }}
          >
            {grouping.families.map(f => <option key={f} value={f}>{f}</option>)}
          </select>
        </label>

        <label className="flex flex-col gap-1">
          <span className={LABEL}>Product</span>
          <select className={INPUT} value={product} onChange={e => setSelected(e.target.value)}>
            {familyProducts.map(p => <option key={p.product} value={p.product}>{p.product}</option>)}
          </select>
        </label>

        <label className="flex flex-col gap-1">
          <span className={LABEL}>Cartons</span>
          <input
            className={`${INPUT} font-mono w-24`} type="number" min={0} inputMode="numeric"
            value={typed} placeholder={String(prefillCartons)}
            onChange={e => setEntered({ product, value: e.target.value })}
          />
        </label>

        <label className="flex flex-col gap-1">
          <span className={LABEL}>FBA method</span>
          <select className={INPUT} value={methodChoice}
            onChange={e => setMethodChoice(e.target.value as 'AUTO' | FbaMethod)}>
            <option value="AUTO">Auto (cheapest that lands in time)</option>
            {OFFERED_FBA_METHODS.map(m => <option key={m} value={m}>{methodCaption(m)}</option>)}
          </select>
        </label>

        <div className="flex flex-col gap-1">
          <span className={LABEL}>Fill FBA to</span>
          <div className="inline-flex rounded border border-border/40 overflow-hidden self-start"
            role="group" aria-label="How full this delivery leaves FBA">
            {[FBA_BATCH_DOC, FBA_TARGET_DOC].map(d => (
              <button
                key={d} type="button" onClick={() => setBatchDoc(d)} aria-pressed={batchDoc === d}
                title={d === FBA_BATCH_DOC
                  ? `${d} days — skips an early transfer and its handling`
                  : `${d} days — keeps less stock in the expensive warehouse`}
                className={`px-2.5 py-1 text-[11px] font-mono transition-colors ${
                  batchDoc === d
                    ? 'bg-[color:var(--color-text)] text-[color:var(--color-card)]'
                    : 'text-muted hover:text-[color:var(--color-text)]'
                }`}
              >
                {d}d
              </button>
            ))}
          </div>
        </div>

        <label className="flex flex-col gap-1">
          <span className={LABEL}>AWD method</span>
          <select className={INPUT} value={awdMethodChoice}
            onChange={e => setAwdMethodChoice(e.target.value as AwdMethod)}>
            {OFFERED_AWD_METHODS.map(m => <option key={`awd-${m}`} value={m}>{methodCaption(m)}</option>)}
          </select>
        </label>

        <div className="pb-1">
          <div className="font-mono text-[13px] text-[color:var(--color-text)]">
            = {fmt(batchUnits)} units <span className="text-[10px] text-muted">({fmt(packageQuantity)} per carton)</span>
          </div>
          <div className="text-[9px] text-subtle">
            {isDefaulted
              ? `Defaulted from ${fmt(readyUnits)} units ready at the manufacturer`
              : `Entered — the manufacturer has ${fmt(readyUnits)} units ready (${fmt(prefillCartons)} cartons)`}
          </div>
        </div>
      </div>

      {/* ── Data-quality notices ── */}
      {inventoryError && (
        <Notice tone="negative" text={`Stock levels failed to load (${inventoryError}). FBA and AWD on hand are being read as zero, which will oversize the FBA leg. Do not act on this split until inventory loads.`} />
      )}
      {!constants.loaded && (
        <Notice tone="warning" text={`Transit times and the FBA inbound buffer are built-in defaults, not live DE_LIST_OF_VALUES values${constants.error ? ` (${constants.error})` : ' (still loading)'}.`} />
      )}

      {!narrowing.ok ? (
        <div className="text-[11px] leading-snug" style={{ color: 'var(--color-negative)' }}>
          Shipment constants unavailable — no transit days for {narrowing.missing.map(methodCaption).join(', ')}.
          Nothing is planned, because a missing transit time would silently produce an arrival date that is
          simply the ship date. Check the SHIPMENT_TYPE list of values.
        </div>
      ) : !plan ? null : !plan.ok ? (
        <div className="text-[11px]" style={{ color: 'var(--color-negative)' }}>{plan.error}</div>
      ) : (
        <>
          {plan.warnings.map((w, i) => <Notice key={i} tone="warning" text={w} />)}

          <Section title="Ship this batch">
            {plan.legs.map((leg, i) => <LegCard key={`${leg.destination}-${i}`} leg={leg} />)}
            <div className="text-[10px] text-muted">
              FBA cover on the sellable date: <span className="font-mono text-[color:var(--color-text)]">{docLabel(plan.fbaDocAtArrival)}</span>
              {' '}against the {batchDoc}-day delivery fill; FBA and AWD together{' '}
              <span className="font-mono text-[color:var(--color-text)]">{docLabel(plan.combinedDocAtArrival)}</span>
              {' '}against {TOTAL_TARGET_DOC}.
              {plan.fbaOosDate && <> FBA runs out <span className="font-mono" style={{ color: 'var(--color-negative)' }}>{plan.fbaOosDate}</span> without it.</>}
            </div>
          </Section>

          <Section title={`Then transfer AWD → FBA — order at ${FBA_REORDER_DOC} days of cover, restore to ${FBA_TARGET_DOC}`}>
            <TransferTable rows={plan.transfers} />
          </Section>

          {chartRows.length > 0 && (
            <div className={`${CARD} mb-2`}>
              <SplitSimulationChart
                rows={chartRows}
                fbaTargetDoc={FBA_TARGET_DOC}
                fbaReorderDoc={FBA_REORDER_DOC}
                fbaBatchDoc={batchDoc}
                oosLabel={plan.fbaOosDate ?? undefined}
              />
            </div>
          )}

          {/* ── Calculation ledger ── */}
          <details className={CARD}>
            <summary className={`${LABEL} cursor-pointer`}>
              Calculation ledger — every input behind these numbers
            </summary>

            <div className="mt-3 space-y-3">
              <div>
                <div className={`${LABEL} mb-1`}>On hand (never pooled)</div>
                <KV label="FBA — sellable now" value={`${fmt(fbaMap[product] ?? 0)} units`} source="InventorySnapshot" />
                <KV label="AWD — reserve, not sellable" value={`${fmt(awdMap[product] ?? 0)} units`} source="InventorySnapshot" />
                <KV label="In transit to FBA — Amazon's own count"
                  value={reconciliation.snapshotUnits === null ? 'unavailable' : `${fmt(reconciliation.snapshotUnits)} units`}
                  source="InventorySnapshot" />
                <KV label="In transit to AWD — lands in the reserve"
                  value={snapshotInboundAwd === undefined ? 'unavailable' : `${fmt(snapshotInboundAwd)} units`}
                  source="InventorySnapshot" />
                <KV label="Ready at manufacturer" value={`${fmt(readyUnits)} units`} source="InventorySnapshot" />
                <KV label="Snapshot date" value={snapshotDate ?? 'unknown'} source="InventorySnapshot" />
              </div>

              {plan.assumptions.length > 0 && (
                <div>
                  <div className={`${LABEL} mb-1`}>Assumed, because the data did not say</div>
                  {plan.assumptions.map((a, i) => (
                    <div key={i} className="text-[10px] text-muted leading-snug py-0.5">{a}</div>
                  ))}
                </div>
              )}

              <div>
                <div className={`${LABEL} mb-1`}>Cartons → units</div>
                <KV label="Units per carton" value={fmt(packageQuantity)} source="DIM_PRODUCT" />
                <KV label={isDefaulted ? 'Cartons (defaulted from ready stock)' : 'Cartons (entered)'} value={fmt(cartons)} source="Operator input" />
                <KV label="Batch units" value={fmt(plan.units)} source="Split engine" />
              </div>

              <div>
                <div className={`${LABEL} mb-1`}>Sizing the FBA leg</div>
                <KV label="Sellable at FBA (arrival + inbound buffer)" value={plan.sellableDate} source="Split engine" />
                <KV label={`Units to fill FBA to ${batchDoc} days from that date`} value={fmt(plan.targetUnits)} source="Split engine" />
                <KV label="Projected FBA on hand at that date" value={fmt(plan.onHandAtSellable)} source="Split engine" />
                <KV label="Still short after this batch" value={fmt(plan.shortfallUnits)} source="Split engine" />
                <KV label="FBA cover on the sellable date" value={docLabel(plan.fbaDocAtArrival)} source="Split engine" />
                <KV label="FBA + AWD cover on the same date" value={docLabel(plan.combinedDocAtArrival)} source="Split engine" />
                <KV label="Ship date (next Wednesday)" value={plan.shipDate} source="Split engine" />
                <KV label="Method chosen automatically" value={methodCaption(plan.autoMethod)} source="Split engine" />
                <KV label="Overridden by the operator" value={plan.methodOverridden ? 'Yes' : 'No'} source="Operator input" />
                <KV label="AWD leg route" value={methodCaption(plan.awdMethod)} source="Operator input" />
                <KV label="First day FBA runs dry without this batch" value={plan.fbaOosDate ?? 'never inside the horizon'} source="Split engine" />
                <KV label="Left at AWD at the end of the horizon" value={`${fmt(plan.leftoverAwdUnits)} units`} source="Split engine" />
              </div>

              <div>
                <div className={`${LABEL} mb-1`}>
                  Inbound shipments counted — {fmt(reconciliation.rows.filter(r => r.countedUnits > 0).length)} totalling {fmt(reconciliation.countedUnits)} units, arriving between {walk?.from} and {walk?.to} (the period this plan models)
                </div>
                <div className="text-[10px] text-muted leading-snug mb-1.5">{reconciliation.summary}</div>
                <ReconciledLedgerTable rows={reconciliation.rows} />
              </div>

              <div>
                <div className={`${LABEL} mb-1`}>Inbound shipments excluded — {fmt(shipLedger.excluded.length)}</div>
                <ShipmentLedgerTable rows={shipLedger.excluded} greyed />
              </div>

              <div>
                <div className={`${LABEL} mb-1`}>Demand across the horizon</div>
                <DemandLedgerTable rows={demandRows} />
              </div>

              <div>
                <div className={`${LABEL} mb-1`}>Constants</div>
                {transitLedgerEntries(narrowing.transitDays).map(t => (
                  <KV key={t.key} label={`${methodCaption(t.key)} transit${t.used ? '' : ' (listed, never offered here)'}`}
                    value={`${fmt(t.days)} days`} source="DE_LIST_OF_VALUES" />
                ))}
                <KV label="FBA inbound processing buffer (manufacturer → FBA only)" value={`${fmt(constants.fbaInboundBufferDays)} days`} source="DE_LIST_OF_VALUES" />
                <KV label="AWD → FBA transfer lead (door to sellable, no buffer on top)"
                  value={`${fmt(narrowing.transitDays.AWD_TRANSFER)} days`} source="DE_LIST_OF_VALUES" />
                {/* All four levels, each labelled by the decision it governs.
                    They are close together in value and would otherwise be
                    indistinguishable in a list of day counts. */}
                <KV label="FBA cover — ORDERS a transfer at this level (Seller Central min)" value={`${FBA_REORDER_DOC} days`} source="Operating rule" />
                <KV label="FBA cover — a TRANSFER is sized to restore this level (Seller Central max)" value={`${FBA_TARGET_DOC} days`} source="Operating rule" />
                <KV label="FBA cover — a DIRECT delivery from the manufacturer fills to this level" value={`${batchDoc} days`} source={batchDoc === FBA_BATCH_DOC ? 'Operating rule' : 'Operator input'} />
                <KV label="FBA + AWD cover together — the COMBINED position" value={`${TOTAL_TARGET_DOC} days`} source="Operating rule" />
                <KV label="AWD share of the combined target (what is left once a delivery fills FBA)" value={`${reserveDoc} days`} source="Derived from the fill level" />
              </div>
            </div>
          </details>
        </>
      )}
    </div>
  );
}

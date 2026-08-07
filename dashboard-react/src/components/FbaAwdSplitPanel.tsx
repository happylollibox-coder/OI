// Advisory FBA/AWD split panel. Reads the engine (`fbaAwdSplit.ts`), shows the
// operator what to ship where — and, in the calculation ledger, every input the
// recommendation was built from, including the shipments that were EXCLUDED and
// why. Nothing here writes: no BigQuery rows, no bulksheet, no automation.
//
// Layout only. Arithmetic and partitioning live in `splitPanelData.ts`.
import { useMemo, useState } from 'react';
import { planSplit, methodCaption, type FbaMethod, type SplitLeg, type TransferRow } from '../fbaAwdSplit';
import { splitChartWindow, reduceSeriesToWeeks } from '../splitChart';
import { SplitSimulationChart } from './SplitSimulationChart';
import { useShipmentConstants } from '../hooks/useShipmentConstants';
import type { ProjectionShipment } from '../stockProjection';
import type { ForecastDemandMap, ForecastMetaMap, MonthSeasonMap } from '../planTypes';
import {
  TARGET_DOC, OFFERED_FBA_METHODS, docLabel, resolveBatchInput,
  narrowTransitDays, partitionShipmentsForLedger, countedInboundUnits, transitLedgerEntries,
  buildDemandCurve, buildDemandLedger, type LedgerShipment,
} from '../splitPanelData';
import { fmt } from '../utils';

export interface FbaAwdSplitPanelProps {
  products: Array<{ product: string; packageQuantity: number }>;
  fbaMap: Record<string, number>;
  awdMap: Record<string, number>;
  mfrReadyMap: Record<string, number>;
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
            <td className={TD}>{r.status}</td>
            <td className="py-1 text-[10px] text-muted">
              {r.exclusionReason ?? `Adds ${fmt(r.qty)} units to FBA on ${r.arrivalDate}`}
            </td>
          </tr>
        ))}
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
          <th className={TH}>Order</th><th className={TH}>Arrives</th><th className={TH}>Units</th>
          <th className={TH}>Cartons</th><th className={TH}>DOC before</th><th className={TH}>DOC after</th>
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

  const [selected, setSelected] = useState('');
  const [entered, setEntered] = useState<{ product: string; value: string } | null>(null);
  const [methodChoice, setMethodChoice] = useState<'AUTO' | FbaMethod>('AUTO');

  const constants = useShipmentConstants();
  const narrowing = useMemo(() => narrowTransitDays(constants.transitDays), [constants.transitDays]);
  const today = useMemo(() => props.today ?? new Date(), [props.today]);

  // Selection falls back to the first product rather than going stale if the list changes.
  const product = products.some(p => p.product === selected) ? selected : (products[0]?.product ?? '');
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

  // planSplit walks 465 days, so it is memoized on exactly what it reads.
  const plan = useMemo(() => {
    if (!product || !narrowing.ok) return null;
    return planSplit({
      cartons: batch.cartons, packageQuantity: batch.packageQuantity,
      fbaOnHand: fbaMap[product] ?? 0,
      awdOnHand: awdMap[product] ?? 0,
      shipments, curve,
      transitDays: narrowing.transitDays,
      fbaInboundBufferDays: constants.fbaInboundBufferDays,
      today, targetDoc: TARGET_DOC,
      methodOverride: methodChoice === 'AUTO' ? undefined : methodChoice,
    });
  }, [product, narrowing, batch, fbaMap, awdMap, shipments, curve,
    constants.fbaInboundBufferDays, today, methodChoice]);

  const chartRows = useMemo(
    () => (plan?.ok ? reduceSeriesToWeeks(plan.series, splitChartWindow(today, TARGET_DOC)) : []),
    [plan, today]);
  const shipLedger = useMemo(() => partitionShipmentsForLedger(shipments), [shipments]);
  const demandRows = useMemo(() => {
    if (!plan?.ok || !plan.series.length) return [];
    return buildDemandLedger(curve, plan.series[0].date, plan.series[plan.series.length - 1].date);
  }, [plan, curve]);

  if (!products.length) {
    return (
      <div className={CARD}>
        <div className={LABEL}>FBA / AWD Split</div>
        <div className="text-[11px] text-muted mt-2">
          No products to plan — this panel needs at least one product with a package quantity.
        </div>
      </div>
    );
  }

  return (
    <div className={CARD}>
      <div className="flex items-baseline justify-between mb-3">
        <div className={LABEL}>FBA / AWD Split — advisory, nothing is sent</div>
        <div className="text-[9px] text-subtle">Target {TARGET_DOC} days of cover at FBA</div>
      </div>

      {/* ── Inputs ── */}
      <div className="flex flex-wrap items-end gap-4 mb-3">
        <label className="flex flex-col gap-1">
          <span className={LABEL}>Product</span>
          <select className={INPUT} value={product} onChange={e => setSelected(e.target.value)}>
            {products.map(p => <option key={p.product} value={p.product}>{p.product}</option>)}
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
              {' '}against a {TARGET_DOC}-day target.
              {plan.fbaOosDate && <> FBA runs out <span className="font-mono" style={{ color: 'var(--color-negative)' }}>{plan.fbaOosDate}</span> without it.</>}
            </div>
          </Section>

          <Section title="Then transfer AWD → FBA to hold the level">
            <TransferTable rows={plan.transfers} />
          </Section>

          {chartRows.length > 0 && (
            <div className={`${CARD} mb-2`}>
              <SplitSimulationChart rows={chartRows} targetDoc={TARGET_DOC} oosLabel={plan.fbaOosDate ?? undefined} />
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
                <KV label="Ready at manufacturer" value={`${fmt(readyUnits)} units`} source="InventorySnapshot" />
                <KV label="Snapshot date" value={snapshotDate ?? 'unknown'} source="InventorySnapshot" />
              </div>

              <div>
                <div className={`${LABEL} mb-1`}>Cartons → units</div>
                <KV label="Units per carton" value={fmt(packageQuantity)} source="DIM_PRODUCT" />
                <KV label={isDefaulted ? 'Cartons (defaulted from ready stock)' : 'Cartons (entered)'} value={fmt(cartons)} source="Operator input" />
                <KV label="Batch units" value={fmt(plan.units)} source="Split engine" />
              </div>

              <div>
                <div className={`${LABEL} mb-1`}>Sizing the FBA leg</div>
                <KV label={`Units for ${TARGET_DOC} DOC from the sellable date`} value={fmt(plan.targetUnits)} source="Split engine" />
                <KV label="Projected FBA on hand at that date" value={fmt(plan.onHandAtSellable)} source="Split engine" />
                <KV label="Still short after this batch" value={fmt(plan.shortfallUnits)} source="Split engine" />
                <KV label="FBA cover on the sellable date" value={docLabel(plan.fbaDocAtArrival)} source="Split engine" />
                <KV label="Ship date (next Wednesday)" value={plan.shipDate} source="Split engine" />
                <KV label="Method chosen automatically" value={methodCaption(plan.autoMethod)} source="Split engine" />
                <KV label="Overridden by the operator" value={plan.methodOverridden ? 'Yes' : 'No'} source="Operator input" />
                <KV label="First day FBA runs dry without this batch" value={plan.fbaOosDate ?? 'never inside the horizon'} source="Split engine" />
                <KV label="Left at AWD at the end of the horizon" value={`${fmt(plan.leftoverAwdUnits)} units`} source="Split engine" />
              </div>

              <div>
                <div className={`${LABEL} mb-1`}>
                  Inbound shipments counted — {fmt(shipLedger.counted.length)} totalling {fmt(countedInboundUnits(shipLedger))} units
                </div>
                <ShipmentLedgerTable rows={shipLedger.counted} greyed={false} />
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
                <KV label="FBA inbound processing buffer" value={`${fmt(constants.fbaInboundBufferDays)} days`} source="DE_LIST_OF_VALUES" />
                <KV label="FBA days-of-cover target" value={`${TARGET_DOC} days`} source="Operating rule" />
              </div>
            </div>
          </details>
        </>
      )}
    </div>
  );
}

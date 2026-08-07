// Light render smoke test. The panel's arithmetic lives in `splitPanelData.ts`
// and is tested there; this only checks that each of the panel's states puts
// something honest on screen, and that the whole tree mounts.
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import type { ProjectionShipment } from '../stockProjection';
import { useShipmentConstants } from '../hooks/useShipmentConstants';
import { FbaAwdSplitPanel } from './FbaAwdSplitPanel';

vi.mock('../hooks/useShipmentConstants', () => ({ useShipmentConstants: vi.fn() }));
const mockConstants = vi.mocked(useShipmentConstants);

const LIVE = {
  transitDays: { AIR: 10, FAST_SEA: 27, SLOW_SEA: 33, AWD_SLOW_SEA: 63, AWD_TRANSFER: 14 },
  fbaInboundBufferDays: 10,
  loaded: true,
  error: null,
};

const SHIPMENTS: ProjectionShipment[] = [
  { qty: 500, arrival_date: '2026-09-10', status: 'transit', route: 'FAST_SEA' },
  { qty: 900, arrival_date: '2026-11-01', status: 'suggested', route: 'SLOW_SEA' },
];

const baseProps = {
  products: [{ product: 'Pink Lollibox', packageQuantity: 10 }],
  fbaMap: { 'Pink Lollibox': 400 },
  awdMap: { 'Pink Lollibox': 2000 },
  mfrReadyMap: { 'Pink Lollibox': 1000 },
  shipmentsByProduct: { 'Pink Lollibox': SHIPMENTS },
  demandMap: { 'Pink Lollibox': { 202608: 300, 202609: 300, 202610: 310, 202611: 300, 202612: 310, 202701: 310, 202702: 280, 202703: 310, 202704: 300, 202705: 310, 202706: 300, 202707: 310, 202708: 310, 202709: 300, 202710: 310, 202711: 300, 202712: 310 } },
  seasonMap: { Lollibox: { 202611: { peakDays: 12, offseasonDays: 18, holidays: 'BFCM' } } },
  metaMap: { 'Pink Lollibox': { isNew: false, isDraft: false, share: 1, family: 'Lollibox' } },
  snapshotDate: '2026-08-06',
  today: new Date(2026, 7, 7),
};

beforeEach(() => { mockConstants.mockReturnValue(LIVE); });

describe('FbaAwdSplitPanel', () => {
  it('renders the split, the transfer schedule and the ledger without throwing', () => {
    render(<FbaAwdSplitPanel {...baseProps} />);
    expect(screen.getByText(/FBA \/ AWD Split/)).toBeInTheDocument();
    // Prefill: 1000 ready / 10 per carton = 100 cartons = 1,000 units.
    expect(screen.getByText(/= 1,000 units/)).toBeInTheDocument();
    expect(screen.getByRole('spinbutton')).toHaveAttribute('placeholder', '100');
    expect(screen.getByText(/Calculation ledger/)).toBeInTheDocument();
    // The excluded 'suggested' shipment is shown, not silently dropped.
    expect(screen.getByText(/Suggested, not approved/)).toBeInTheDocument();
  });

  it('shows both cover levels, so neither can be mistaken for the other', () => {
    render(<FbaAwdSplitPanel {...baseProps} />);
    expect(screen.getByText(/Target 45 days live at FBA · 100 days FBA \+ AWD combined/)).toBeInTheDocument();
    expect(screen.getByText(/against a 45-day live target/)).toBeInTheDocument();
    expect(screen.getByText(/FBA \+ AWD cover on the same date/)).toBeInTheDocument();
    expect(screen.getByText(/AWD share of the combined target/)).toBeInTheDocument();
  });

  it('shows a past-dated delivery as excluded, never as counted', () => {
    // today = 2026-08-07, so this arrival is behind the start of the engine's walk:
    // walkFba reads no key before today, so it contributes nothing to the projection.
    const past = { qty: 9000, arrival_date: '2026-06-01', status: 'transit' as const, route: 'SLOW_SEA' };
    render(<FbaAwdSplitPanel {...baseProps}
      shipmentsByProduct={{ 'Pink Lollibox': [...SHIPMENTS, past] }} />);
    expect(screen.getByText(/Arrival date has already passed/)).toBeInTheDocument();
    expect(screen.queryByText(/Adds 9,000 units to FBA/)).not.toBeInTheDocument();
    // The counted total is the in-window shipment alone, not 9,500.
    expect(screen.getByText(/Inbound shipments counted — 1 totalling 500 units/)).toBeInTheDocument();
  });

  it('trims a shipment record down to Amazon"s in-transit figure, and says so', () => {
    // The records claim 500 units landing 2026-09-10; Amazon says 200 are on
    // the water. The row survives at 200, and the ledger shows both numbers.
    render(<FbaAwdSplitPanel {...baseProps} inTransitFbaMap={{ 'Pink Lollibox': 200 }} />);
    expect(screen.getByText(/Inbound shipments counted — 1 totalling 200 units/)).toBeInTheDocument();
    expect(screen.getByText(/records claim 500 units inbound to FBA; Amazon's snapshot says 200/)).toBeInTheDocument();
    expect(screen.getByText(/300 units were removed from the projection, latest arrival first/)).toBeInTheDocument();
    expect(screen.getByText('Trimmed')).toBeInTheDocument();
    expect(screen.getByText(/Trimmed to 200 of 500 units on 2026-09-10/)).toBeInTheDocument();
  });

  it('marks a dropped row as its own verdict, not as an exclusion', () => {
    // A trimmed or dropped row is confirmed, FBA-bound and in-window — it is
    // Amazon's count that overrode it, which is a different thing from the
    // reasons in the excluded table and must not be dressed up as one.
    render(<FbaAwdSplitPanel {...baseProps} inTransitFbaMap={{ 'Pink Lollibox': 0 }} />);
    expect(screen.getByText(/Inbound shipments counted — 0 totalling 0 units/)).toBeInTheDocument();
    expect(screen.getByText('Dropped')).toBeInTheDocument();
    expect(screen.getByText(/Amazon's in-transit total is already met by later arrivals/)).toBeInTheDocument();
    // Still greyed out separately for the genuinely-excluded suggestion.
    expect(screen.getByText(/Suggested, not approved/)).toBeInTheDocument();
  });

  it('says the snapshot was unavailable rather than reading a missing figure as zero', () => {
    render(<FbaAwdSplitPanel {...baseProps} />);
    expect(screen.getByText(/Inbound shipments counted — 1 totalling 500 units/)).toBeInTheDocument();
    expect(screen.getByText(/Amazon's in-transit figure is unavailable/)).toBeInTheDocument();
    expect(screen.getByText(/this inbound figure is unverified/)).toBeInTheDocument();
    expect(screen.getByText('Kept')).toBeInTheDocument();
    expect(screen.getByText(/Adds 500 units to FBA on 2026-09-10/)).toBeInTheDocument();
  });

  it('counts stock on the water to AWD and states the arrival date it assumed', () => {
    render(<FbaAwdSplitPanel {...baseProps} inTransitAwdMap={{ 'Pink Lollibox': 1056 }} />);
    expect(screen.getByText(/Assumed, because the data did not say/)).toBeInTheDocument();
    // today 2026-08-07 + AWD Slow Sea 63d = 2026-10-09.
    expect(screen.getByText(/1056 units already in transit to AWD carry no arrival date/)).toBeInTheDocument();
    expect(screen.getByText(/assumed to land 2026-10-09 — AWD Slow Sea \(63d\) from today/)).toBeInTheDocument();
    expect(screen.getByText(/In transit to AWD — lands in the reserve/)).toBeInTheDocument();
  });

  it('never offers Air as an FBA route', () => {
    render(<FbaAwdSplitPanel {...baseProps} />);
    const options = screen.getAllByRole('option').map(o => o.textContent);
    expect(options).toContain('Slow Sea');
    expect(options).toContain('Fast Sea');
    expect(options.some(o => /^Air$/.test(o ?? ''))).toBe(false);
  });

  it('refuses to plan and says why when a transit constant is missing', () => {
    mockConstants.mockReturnValue({
      ...LIVE, loaded: false, error: 'LOV endpoint unreachable',
      transitDays: { SLOW_SEA: 33, FAST_SEA: 27 },
    });
    render(<FbaAwdSplitPanel {...baseProps} />);
    expect(screen.getByText(/Shipment constants unavailable/)).toBeInTheDocument();
    expect(screen.getByText(/AWD Slow Sea, AWD → FBA Transfer/)).toBeInTheDocument();
    expect(screen.queryByText(/Calculation ledger/)).not.toBeInTheDocument();
  });

  it('surfaces an inventory load failure prominently rather than sizing off zeroes', () => {
    render(<FbaAwdSplitPanel {...baseProps} inventoryError="Cube HTTP 500" />);
    expect(screen.getByText(/Stock levels failed to load \(Cube HTTP 500\)/)).toBeInTheDocument();
  });

  it('warns that transit times are defaults when the LOV has not loaded', () => {
    mockConstants.mockReturnValue({ ...LIVE, loaded: false, error: null });
    render(<FbaAwdSplitPanel {...baseProps} />);
    expect(screen.getByText(/built-in defaults, not live DE_LIST_OF_VALUES/)).toBeInTheDocument();
  });

  it('shows the engine error instead of a plan when the forecast is empty', () => {
    render(<FbaAwdSplitPanel {...baseProps} demandMap={{}} />);
    expect(screen.getByText(/No demand forecast for this product/)).toBeInTheDocument();
    expect(screen.queryByText(/Calculation ledger/)).not.toBeInTheDocument();
  });

  it('says so rather than rendering an empty picker when there are no products', () => {
    render(<FbaAwdSplitPanel {...baseProps} products={[]} />);
    expect(screen.getByText(/No products to plan/)).toBeInTheDocument();
    expect(screen.queryByRole('combobox')).not.toBeInTheDocument();
  });
});

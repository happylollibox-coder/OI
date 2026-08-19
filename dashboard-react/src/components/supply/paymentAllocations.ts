/**
 * Resolve a payment's comma-joined allocation IDs against the PO and Other-PO
 * ledgers.  No React — kept separate so the resolution is unit-testable.
 *
 * The Payments tab used to do `ids.map(find).filter(Boolean)`, which silently
 * dropped every ID it could not match: Other-POs (real money, just in
 * DE_OTHER_PO) and true orphans (a PO that was deleted out from under the
 * payment) both vanished from the expansion with no signal.  Every ID must
 * come back classified so the UI can render it.
 */

/** Minimum shape needed from a PO row — keeps this file free of page types.
 *  Callers pass their own richer row type; the generics carry it through so
 *  the resolved `po` / `otherPo` stay fully typed at the call site. */
export interface AllocPo {
  purchase_order_id: string;
}

/** Minimum shape needed from an Other-PO row. */
export interface AllocOtherPo {
  other_po_id: string;
}

/**
 * `unknown` means "cannot tell" — the Other-PO ledger did not load, so an
 * unmatched ID might be a perfectly good Other-PO. Never shown as an error;
 * only `orphan` is, and only when both ledgers were actually available.
 */
export type AllocationKind = 'po' | 'other_po' | 'orphan' | 'unknown';

export interface ResolvedAllocation<P extends AllocPo, O extends AllocOtherPo> {
  id: string;
  kind: AllocationKind;
  /** Set when kind === 'po'. */
  po?: P;
  /** Set when kind === 'other_po'. */
  otherPo?: O;
}

/** Split the cube's STRING_AGG'd `purchase_order_ids` into individual IDs. */
export function parseAllocationIds(joined: string | null | undefined): string[] {
  if (!joined) return [];
  const seen = new Set<string>();
  const out: string[] = [];
  for (const raw of joined.split(',')) {
    const id = raw.trim();
    if (!id || seen.has(id)) continue;
    seen.add(id);
    out.push(id);
  }
  return out;
}

/**
 * Classify each allocation ID. Order is preserved, and NOTHING is dropped.
 *
 * `otherPosLoaded` must be true before an unmatched ID is called an `orphan`.
 * The Other-PO ledger comes from Flask, which is often down in local dev — if
 * it did not load, every Other-PO would otherwise be reported as missing
 * money, which is a far worse lie than the silent drop this replaced.
 */
export function resolvePaymentAllocations<P extends AllocPo, O extends AllocOtherPo>(
  joined: string | null | undefined,
  pos: readonly P[],
  otherPos: readonly O[],
  otherPosLoaded: boolean,
): ResolvedAllocation<P, O>[] {
  const poById = new Map(pos.map((p) => [p.purchase_order_id, p]));
  const otherById = new Map(otherPos.map((o) => [o.other_po_id, o]));
  return parseAllocationIds(joined).map((id) => {
    const po = poById.get(id);
    if (po) return { id, kind: 'po' as const, po };
    const otherPo = otherById.get(id);
    if (otherPo) return { id, kind: 'other_po' as const, otherPo };
    return { id, kind: otherPosLoaded ? ('orphan' as const) : ('unknown' as const) };
  });
}

/** How many allocations point at nothing — drives the row-level warning. */
export function countOrphans(
  allocations: readonly { kind: AllocationKind }[],
): number {
  return allocations.filter((a) => a.kind === 'orphan').length;
}

/**
 * A likely intended target for an orphaned ID.
 *
 * PO-ID generation appends a `_1`, `_2`, … collision suffix, so an orphan is
 * usually a stale reference to a duplicate PO that was later deleted while the
 * un-suffixed PO is alive. Returns null when there is no such candidate —
 * this only ever suggests, it never re-points anything.
 */
export function suggestOrphanTarget<P extends AllocPo>(
  orphanId: string,
  pos: readonly P[],
): string | null {
  const stripped = orphanId.replace(/_\d+$/, '');
  if (stripped === orphanId) return null;
  return pos.some((p) => p.purchase_order_id === stripped) ? stripped : null;
}

import { useEffect, useState } from 'react';
import { apiFetch } from '../utils/apiFetch';
import { fShort, fR } from '../utils';

interface Cell {
  status: 'ok' | 'missing' | 'redundant';
  n_enabled: number;
  n_any: number;
  impressions: number;
  clicks: number;
  units: number;
  net_roas: number | null;
  campaigns: string | null;
}
interface AutoRow extends Cell { asin: string; product_short_name: string; }
interface Family {
  family: string;
  roles: Record<string, Cell>;
  autos: AutoRow[];
  n_auto_missing: number;
  n_role_missing: number;
  n_missing: number;
  n_redundant: number;
  complete: boolean;
}
interface Store { label: string; roles: Record<string, Cell>; complete: boolean; }
interface CoverageData { family_roles: string[]; days: number; store: Store; families: Family[]; }

const ROLE_LABEL: Record<string, string> = {
  AUTO: 'Auto',
  BRAND_DEFENSE: 'Brand Defense',
  PRODUCT_DEFENSE: 'Product Defense',
  EXACT: 'Exact',
  BROAD: 'Broad',
  PHRASE: 'Phrase',
  COMPETITOR: 'Competitor',
  SB_VIDEO: 'SB / Video',
};

function StatusPill({ c }: { c: Cell }) {
  const tone = c.status === 'ok' ? 'text-emerald-400' : c.status === 'redundant' ? 'text-amber-400' : 'text-red-400';
  const label = c.status === 'ok' ? '✓ defined' : c.status === 'redundant' ? `⚠ ${c.n_enabled} campaigns` : '✗ to do';
  return <span className={`${tone} font-semibold text-[10px]`}>{label}</span>;
}

function Metrics({ c }: { c: Cell }) {
  if (!c.clicks) return <span className="text-faint text-[9px]">no data</span>;
  return (
    <span className="text-[9px] tabular-nums text-muted">
      {c.net_roas != null && <span className={c.net_roas >= 1 ? 'text-emerald-400' : 'text-red-400'}>{fR(c.net_roas)}</span>}
      {' · '}{fShort(c.clicks)} clk · {fShort(c.impressions)} imp · {c.units}u
    </span>
  );
}

/** Ad coverage scan at each role's own grain (architecture/INTENT_CAMPAIGN_MODEL.md §F):
 *  Auto = per product · Brand Defense + offense = per family · Product Defense = store.
 *  All status/role logic lives in /api/coverage (BigQuery); this only renders. */
export function CoveragePage() {
  const [data, setData] = useState<CoverageData | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [open, setOpen] = useState<string | null>(null); // family name or '__STORE__'

  useEffect(() => {
    apiFetch('/api/coverage')
      .then(r => (r.ok ? r.json() : Promise.reject(new Error(`HTTP ${r.status}`))))
      .then(d => (d.error ? setErr(d.error) : setData(d)))
      .catch(e => setErr(String(e)));
  }, []);

  if (err) return <div className="p-6 text-sm text-red-400">Coverage scan failed: {err}</div>;
  if (!data) return <div className="p-6 text-sm text-muted">Scanning ad coverage…</div>;

  const btnTone = (complete: boolean, nMissing: number) =>
    complete ? 'border-emerald-500/50 bg-emerald-500/10 hover:bg-emerald-500/20'
      : nMissing > 0 ? 'border-red-500/40 bg-red-500/10 hover:bg-red-500/20'
      : 'border-amber-500/40 bg-amber-500/10 hover:bg-amber-500/20';

  const openFam = data.families.find(f => f.family === open);
  const openStore = open === '__STORE__';

  return (
    <div className="p-4">
      <div className="flex items-center gap-3 mb-4">
        <h1 className="text-lg font-bold text-heading">🩺 Ad Coverage Scan</h1>
        <span className="text-[11px] text-muted">last {data.days}d · green = everything defined · click to see the mapping</span>
      </div>

      <div className="flex flex-wrap gap-2 mb-2">
        {/* Store button — Product Defense is cross-family */}
        <button
          onClick={() => setOpen(o => (o === '__STORE__' ? null : '__STORE__'))}
          className={`rounded-lg border px-4 py-3 text-left min-w-[150px] transition ${btnTone(data.store.complete, data.store.roles.PRODUCT_DEFENSE?.status === 'missing' ? 1 : 0)} ${open === '__STORE__' ? 'ring-2 ring-blue-400/60' : ''}`}
        >
          <div className="text-xs font-bold text-heading">🏬 Store</div>
          <div className="text-[9px] text-muted">cross-family · Product Defense</div>
          <div className="mt-1"><StatusPill c={data.store.roles.PRODUCT_DEFENSE} /></div>
        </button>

        {data.families.map(f => (
          <button
            key={f.family}
            onClick={() => setOpen(o => (o === f.family ? null : f.family))}
            className={`rounded-lg border px-4 py-3 text-left min-w-[150px] transition ${btnTone(f.complete, f.n_missing)} ${open === f.family ? 'ring-2 ring-blue-400/60' : ''}`}
          >
            <div className="text-xs font-bold text-heading">{f.family}</div>
            <div className="text-[9px] text-muted">{f.autos.length} products</div>
            <div className="mt-1 text-[10px] font-semibold">
              {f.complete
                ? <span className="text-emerald-400">✓ all defined</span>
                : <>
                    {f.n_missing > 0 && <span className="text-red-400">{f.n_missing} to do</span>}
                    {f.n_missing > 0 && f.n_redundant > 0 && <span className="text-faint"> · </span>}
                    {f.n_redundant > 0 && <span className="text-amber-400">{f.n_redundant} redundant</span>}
                  </>}
            </div>
          </button>
        ))}
      </div>

      {(openFam || openStore) && (
        <div className="mt-3 border border-border/40 rounded-lg bg-white/[0.01] max-w-[860px]">
          <div className="flex items-center justify-between px-4 py-2.5 border-b border-border/20 bg-white/[0.02]">
            <div className="text-sm font-semibold">
              {openStore ? '🏬 Store — cross-family' : openFam!.family}
              <span className="text-faint text-xs ml-2 font-normal">mapping — done vs to do</span>
            </div>
            <button onClick={() => setOpen(null)} className="text-faint hover:text-text text-lg leading-none px-1" title="Collapse">×</button>
          </div>

          <div className="p-4 space-y-4 text-xs">
            {openStore ? (
              <Section title="Product Defense — store, cross-family">
                <RoleRow role="PRODUCT_DEFENSE" c={data.store.roles.PRODUCT_DEFENSE} />
              </Section>
            ) : (
              <>
                <Section title="Family campaigns (family × match-type × intent)">
                  {data.family_roles.map(role => (
                    <RoleRow key={role} role={role} c={openFam!.roles[role]} />
                  ))}
                  <div className="text-[9px] text-faint mt-2">
                    Intent-level checks (per family × match-type × intent) arrive with the intent model — this is family-level presence for now.
                  </div>
                </Section>

                <Section title={`Auto — per product (${openFam!.autos.length})`}>
                  {openFam!.autos.map(a => (
                    <div key={a.asin} className="flex items-center gap-2 py-1 border-b border-border-faint last:border-0">
                      <span className="text-heading truncate max-w-[170px]" title={a.asin}>{a.product_short_name || a.asin}</span>
                      <span className="ml-auto"><Metrics c={a} /></span>
                      <span className="w-[92px] text-right"><StatusPill c={a} /></span>
                    </div>
                  ))}
                </Section>
              </>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div>
      <div className="text-[9px] text-faint uppercase tracking-wide mb-1">{title}</div>
      <div className="bg-surface rounded p-2">{children}</div>
    </div>
  );
}

function RoleRow({ role, c }: { role: string; c: Cell }) {
  return (
    <div className="py-1 border-b border-border-faint last:border-0">
      <div className="flex items-center gap-2">
        <span className="text-heading font-medium">{ROLE_LABEL[role] ?? role}</span>
        <span className="ml-auto"><Metrics c={c} /></span>
        <span className="w-[92px] text-right"><StatusPill c={c} /></span>
      </div>
      {c.campaigns && (
        <div className="text-[9px] text-muted mt-0.5 pl-1 truncate" title={c.campaigns}>{c.campaigns}</div>
      )}
      {!c.campaigns && c.n_any > 0 && (
        <div className="text-[9px] text-faint mt-0.5 pl-1">{c.n_any} paused/archived with history</div>
      )}
    </div>
  );
}

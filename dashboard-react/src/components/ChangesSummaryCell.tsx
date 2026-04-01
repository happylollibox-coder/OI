import { useState, useRef, useEffect } from 'react';
import { createPortal } from 'react-dom';
import { deltaStr, fM } from '../utils';

export interface ChangesSummaryData {
  status: string;
  sd: number;
  cd: number;
  pd: number;
  roasDelta: number;
  orgDelta: number;
  prevSales?: number;
  prevAdCost?: number;
  prevNetProfit?: number;
}

function dotColor(delta: number): string {
  if (delta > 0.5) return 'bg-emerald-500';
  if (delta < -0.5) return 'bg-red-500';
  return 'bg-zinc-500';
}

/** Short status for badge: first phrase before " – " or ". " */
function shortStatus(status: string): string {
  return status.split(' – ')[0].split('. ')[0];
}

export function ChangesSummaryCell({
  data,
  positiveCount,
  totalCount,
}: {
  data: ChangesSummaryData;
  positiveCount?: number;
  totalCount?: number;
}) {
  const [show, setShow] = useState(false);
  const [coords, setCoords] = useState({ x: 0, y: 0, above: true });
  const ref = useRef<HTMLSpanElement>(null);

  useEffect(() => {
    if (show && ref.current) {
      const r = ref.current.getBoundingClientRect();
      setCoords({ x: r.left + r.width / 2, y: r.top < 60 ? r.bottom : r.top, above: r.top >= 60 });
    }
  }, [show]);

  const { status, sd, cd, pd, roasDelta, orgDelta, prevSales, prevAdCost, prevNetProfit } = data;
  const lines: string[] = [
    `Sales ${deltaStr(sd)}${prevSales != null ? ` (prev ${fM(prevSales)})` : ''}`,
    `Ads Spend ${deltaStr(cd)}${prevAdCost != null ? ` (prev ${fM(prevAdCost)})` : ''}`,
    `Net Profit ${deltaStr(pd)}${prevNetProfit != null ? ` (prev ${fM(prevNetProfit)})` : ''}`,
    `ROAS ${deltaStr(roasDelta)}`,
    `Organic % ${deltaStr(orgDelta)}`,
    '',
    status,
  ];
  const tooltipText = lines.join('\n');

  return (
    <span
      ref={ref}
      className="inline-flex items-center gap-1.5 cursor-help"
      onMouseEnter={() => setShow(true)}
      onMouseLeave={() => setShow(false)}
    >
      <span className="text-[10px] font-medium text-subtle truncate max-w-[100px]">{shortStatus(status)}</span>
      <span className="inline-flex items-center gap-0.5 shrink-0">
        {[sd, cd, pd, roasDelta, orgDelta].map((d, i) => (
          <span key={i} className={`inline-block w-1.5 h-1.5 rounded-full ${dotColor(d)}`} title={['Sales', 'Ads Spend', 'Net Profit', 'Ads ROAS', 'Organic %'][i]} />
        ))}
      </span>
      {totalCount != null && totalCount > 0 && (
        <span className="text-[10px] font-mono text-faint shrink-0">
          {positiveCount ?? 0}/{totalCount}
        </span>
      )}
      {show &&
        createPortal(
          <span
            className="fixed z-[9999] px-3 py-2 rounded-lg bg-card border border-border-strong text-[11px] text-muted leading-relaxed shadow-xl whitespace-pre-line font-normal normal-case tracking-normal pointer-events-none max-w-[280px]"
            style={{
              left: coords.x,
              top: coords.above ? coords.y : coords.y + 6,
              transform: coords.above ? 'translate(-50%, -100%) translateY(-6px)' : 'translate(-50%, 0)',
            }}
          >
            {tooltipText}
          </span>,
          document.body
        )}
    </span>
  );
}

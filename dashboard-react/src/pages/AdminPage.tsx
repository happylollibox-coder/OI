import { useState } from 'react';
import { RefreshCw } from 'lucide-react';
import { Card } from '../components/Card';
import { Section } from '../components/Section';
import { usePageSummary } from '../components/PageSummaryBar';

export function AdminPage() {
  const [output, setOutput] = useState<string>('');
  const [running, setRunning] = useState<boolean>(false);
  const [lastOpSuccess, setLastOpSuccess] = useState<boolean | null>(null);

  const refresh = async () => {
    setRunning(true);
    setOutput('Running… Fetching data from BigQuery. This may take 1–2 minutes.');
    setLastOpSuccess(null);
    try {
      const res = await fetch('/api/admin/refresh', { method: 'POST' });
      const data = await res.json();
      setOutput(data.output || 'No output');
      setLastOpSuccess(data.success);
    } catch (e) {
      setOutput(`Error: ${e instanceof Error ? e.message : String(e)}`);
      setLastOpSuccess(false);
    } finally {
      setRunning(false);
    }
  };

  usePageSummary({ title: 'Admin', items: [{ label: 'Settings', value: 'Admin' }] });
  return (
    <div className="animate-in">
      <Section title="Operations">
        <div className="flex flex-wrap gap-3 items-center">
          <button
            onClick={refresh}
            disabled={running}
            className="flex items-center gap-2 px-4 py-2.5 rounded-xl font-semibold text-sm border border-border bg-card hover:bg-white/[.04] hover:border-blue-500/40 disabled:opacity-50 disabled:cursor-not-allowed transition-all"
          >
            <RefreshCw size={18} className={running ? 'animate-spin' : ''} />
            Refresh Data
          </button>
          {running && (
            <span className="text-sm text-subtle">Running… This may take 1–2 minutes. Do not refresh the page.</span>
          )}
        </div>
      </Section>

      {output && (
        <Section title="Output" count={lastOpSuccess === true ? '✅ Success' : lastOpSuccess === false ? '❌ Failed' : undefined}>
          <Card className="!p-0 overflow-hidden">
            <pre className="p-4 text-xs font-mono text-subtle overflow-x-auto max-h-[400px] overflow-y-auto whitespace-pre-wrap">
              {output}
            </pre>
          </Card>
        </Section>
      )}
    </div>
  );
}

import { useState, useEffect } from 'react';
import { RefreshCw, CheckCircle, XCircle, Clock, ChevronDown, ChevronRight, AlertTriangle } from 'lucide-react';
import { Card } from '../components/Card';
import { Section } from '../components/Section';
import { usePageSummary } from '../components/PageSummaryBar';
import { Badge } from '../components/Badge';
import { NegativePhrases } from '../components/NegativePhrases';

interface PipelineTask {
  procedure_name: string;
  status: string;
  error_message: string | null;
  duration_seconds: number;
}

interface PipelineRun {
  run_id: string;
  run_date: string;
  start_time: string;
  end_time: string;
  total_duration_seconds: number;
  total_tasks: number;
  success_count: number;
  fail_count: number;
  tasks: PipelineTask[];
}

export function AdminPage() {
  const [output, setOutput] = useState<string>('');
  const [running, setRunning] = useState<boolean>(false);
  const [lastOpSuccess, setLastOpSuccess] = useState<boolean | null>(null);
  
  const [runs, setRuns] = useState<PipelineRun[]>([]);
  const [loadingLogs, setLoadingLogs] = useState<boolean>(true);
  const [expandedRunId, setExpandedRunId] = useState<string | null>(null);

  const fetchLogs = async () => {
    setLoadingLogs(true);
    try {
      const res = await fetch('/api/admin/pipeline-logs');
      if (res.ok) {
        const data = await res.json();
        if (data.success) setRuns(data.runs || []);
      }
    } catch (e) {
      console.error('Failed to fetch pipeline logs', e);
    } finally {
      setLoadingLogs(false);
    }
  };

  useEffect(() => {
    fetchLogs();
  }, []);

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
    <div className="animate-in space-y-6">
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
          <button
            onClick={async () => {
              setRunning(true);
              setOutput('Refreshing suggestions (Product → Inventory → Forecast → Shipment Plan)...');
              setLastOpSuccess(null);
              try {
                const res = await fetch('/api/admin/refresh-shipments', { method: 'POST' });
                const data = await res.json();
                setOutput(data.output || 'No output');
                setLastOpSuccess(data.success);
              } catch (e) {
                setOutput(`Error: ${e instanceof Error ? e.message : String(e)}`);
                setLastOpSuccess(false);
              } finally {
                setRunning(false);
              }
            }}
            disabled={running}
            className="flex items-center gap-2 px-4 py-2.5 rounded-xl font-semibold text-sm border border-border bg-card hover:bg-white/[.04] hover:border-blue-500/40 disabled:opacity-50 disabled:cursor-not-allowed transition-all"
          >
            <RefreshCw size={18} className={running ? 'animate-spin' : ''} />
            Refresh Suggestions
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

      <Section title="Negative Phrases" count={`Per-Product Keyword Negatives`}>
        <NegativePhrases />
      </Section>

      <Section title="Pipeline Run Logs">
        <div className="flex justify-between items-center mb-4">
          <div className="text-sm text-subtle">Recent BigQuery orchestrator runs.</div>
          <button 
            onClick={fetchLogs} 
            disabled={loadingLogs}
            className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold rounded-lg bg-surface hover:bg-white/[.04] border border-border transition-colors disabled:opacity-50"
          >
            <RefreshCw size={14} className={loadingLogs ? 'animate-spin' : ''} />
            Refresh Logs
          </button>
        </div>
        
        {loadingLogs && runs.length === 0 ? (
          <div className="py-8 text-center text-subtle text-sm animate-pulse">Loading logs...</div>
        ) : runs.length === 0 ? (
          <Card className="p-8 text-center text-subtle border-dashed">
            No pipeline logs found.
          </Card>
        ) : (
          <div className="space-y-3">
            {runs.map(run => {
              const isFailed = run.fail_count > 0;
              const isExpanded = expandedRunId === run.run_id;
              
              return (
                <Card key={run.run_id} className={`!p-0 overflow-hidden border ${isFailed ? 'border-red-500/20' : 'border-border'}`}>
                  <div 
                    className={`flex items-center justify-between p-4 cursor-pointer hover:bg-white/[.02] transition-colors ${isFailed ? 'bg-red-500/[.02]' : ''}`}
                    onClick={() => setExpandedRunId(isExpanded ? null : run.run_id)}
                  >
                    <div className="flex items-center gap-3">
                      {isExpanded ? <ChevronDown size={18} className="text-subtle" /> : <ChevronRight size={18} className="text-subtle" />}
                      {isFailed ? <XCircle size={20} className="text-red-400" /> : <CheckCircle size={20} className="text-emerald-400" />}
                      <div>
                        <div className="font-semibold text-sm flex items-center gap-2">
                          Run: {run.run_date}
                          {isFailed && <Badge variant="red">{run.fail_count} Failed</Badge>}
                        </div>
                        <div className="text-xs text-subtle flex items-center gap-3 mt-1">
                          <span className="flex items-center gap-1"><Clock size={12} /> {Math.round(run.total_duration_seconds / 60)}m {run.total_duration_seconds % 60}s</span>
                          <span>•</span>
                          <span>{run.success_count}/{run.total_tasks} tasks successful</span>
                          <span>•</span>
                          <span className="font-mono">{new Date(run.start_time).toLocaleTimeString()} — {new Date(run.end_time).toLocaleTimeString()}</span>
                        </div>
                      </div>
                    </div>
                  </div>
                  
                  {isExpanded && (
                    <div className="border-t border-border bg-black/20 p-4">
                      <table className="w-full text-left text-xs">
                        <thead>
                          <tr className="text-faint border-b border-border-faint">
                            <th className="pb-2 font-medium">Task / Procedure</th>
                            <th className="pb-2 font-medium">Status</th>
                            <th className="pb-2 font-medium text-right">Duration</th>
                          </tr>
                        </thead>
                        <tbody className="divide-y divide-border-faint">
                          {run.tasks.map((task, i) => (
                            <tr key={i}>
                              <td className="py-2.5">
                                <div className="font-mono text-[11px] text-blue-300">{task.procedure_name}</div>
                                {task.error_message && (
                                  <div className="mt-1.5 flex items-start gap-1.5 text-[11px] text-red-400 bg-red-500/10 p-2 rounded border border-red-500/20">
                                    <AlertTriangle size={12} className="shrink-0 mt-0.5" />
                                    <span className="font-mono break-all">{task.error_message}</span>
                                  </div>
                                )}
                              </td>
                              <td className="py-2.5">
                                {task.status === 'OK' ? (
                                  <Badge variant="green">OK</Badge>
                                ) : (
                                  <Badge variant="red">FAILED</Badge>
                                )}
                              </td>
                              <td className="py-2.5 text-right font-mono text-subtle">
                                {task.duration_seconds}s
                              </td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                  )}
                </Card>
              );
            })}
          </div>
        )}
      </Section>
    </div>
  );
}


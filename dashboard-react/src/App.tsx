import { useState, useCallback, useEffect } from 'react';
import { useUnifiedData } from './hooks/useUnifiedData';
import { useGroundTruth } from './hooks/useGroundTruth';
import { useTheme } from './hooks/useTheme';
import { FiltersProvider, useFilters } from './hooks/useFilters';
import { Header } from './components/Header';
import { Sidebar } from './components/Sidebar';
import { FilterBar } from './components/FilterBar';
import { DashboardSkeleton } from './components/Skeleton';
import { PageSummaryBar, PageSummaryProvider } from './components/PageSummaryBar';
import { HomePage } from './pages/HomePage';
import { ActionsPage } from './pages/ActionsPage';
import { PeakPage } from './pages/PeakPage';
import { FamilyPage } from './pages/FamilyPage';
import { LearnPage } from './pages/LearnPage';
import { KeywordsPage } from './pages/KeywordsPage';
import { LogPage } from './pages/LogPage';
import { HealthPage } from './pages/HealthPage';
import { ExperimentPage } from './pages/ExperimentPage';
import { AdsPerformancePage } from './pages/AdsPerformancePage';
import { StrategiesPage } from './pages/StrategiesPage';
import { AdminPage } from './pages/AdminPage';
import { DoPage } from './pages/DoPage';
import { BrandPage } from './pages/BrandPage';
import { PlanPage } from './pages/PlanPage';
import { SupplyPage } from './pages/SupplyPage';
import { AlertsPage } from './pages/AlertsPage';
import { ProductsPage } from './pages/ProductsPage';
import { KpiPage } from './pages/KpiPage';
import { DoQueueProvider } from './hooks/useDoQueue';
import { AuthProvider, useAuth } from './contexts/AuthContext';
import { LoginScreen } from './components/LoginScreen';
import type { PageId, FamilyName } from './types';

export default function App() {
  return (
    <AuthProvider>
      <DoQueueProvider>
        <FiltersProvider>
          <PageSummaryProvider>
            <AppWrapper />
          </PageSummaryProvider>
        </FiltersProvider>
      </DoQueueProvider>
    </AuthProvider>
  );
}

function AppWrapper() {
  const { isAuthenticated } = useAuth();
  
  if (!isAuthenticated) {
    return <LoginScreen />;
  }
  
  return <AppInner />;
}

function AppInner() {
  const { data, loading, fromCube } = useUnifiedData();
  const gt = useGroundTruth();
  const { mode: themeMode, toggle: toggleTheme } = useTheme();
  const { filters, setFilter } = useFilters();
  const [page, setPage] = useState<PageId>('home');
  const [experimentId, setExperimentId] = useState<string | null>(null);
  const [alertBadge, setAlertBadge] = useState<{ critical: number; warning: number; total: number } | undefined>();
  const [adminBadge, setAdminBadge] = useState<'error' | 'ok' | null>(null);

  // Fetch alert count for sidebar badge
  useEffect(() => {
    const fetchCount = () => {
      fetch('/api/alerts/count').then(r => r.ok ? r.json() : null).then(d => {
        if (d) setAlertBadge({ critical: d.critical || 0, warning: d.warning || 0, total: d.total || 0 });
      }).catch(() => {});
      
      fetch('/api/admin/pipeline-logs').then(r => r.ok ? r.json() : null).then(d => {
        if (d && d.success && d.runs && d.runs.length > 0) {
          const latestRun = d.runs[0];
          setAdminBadge(latestRun.fail_count > 0 ? 'error' : 'ok');
        }
      }).catch(() => {});
    };
    fetchCount();
    const interval = setInterval(fetchCount, 5 * 60 * 1000); // refresh every 5 min
    return () => clearInterval(interval);
  }, []);

  const navigate = useCallback((p: string, f?: FamilyName, expId?: string) => {
    setPage(p as PageId);
    if (f !== undefined) setFilter('family', f);
    if (expId) setExperimentId(expId);
  }, [setFilter]);

  if (loading) {
    return (
      <>
        <Header data={data} onNav={navigate} />
        <Sidebar activePage={page} activeFamily={filters.family} onNav={navigate} themeMode={themeMode} onToggleTheme={toggleTheme} />
        <main className="fixed top-14 left-[72px] right-0 bottom-0 overflow-y-auto px-8 py-5 pb-16 scroll-smooth">
          <DashboardSkeleton />
        </main>
      </>
    );
  }

  const renderPage = () => {
    switch (page) {
      case 'home': return <HomePage data={data} onNav={navigate} />;
      case 'actions': return <ActionsPage data={data} matchAction={gt.matchAction} />;
      case 'peak': return <PeakPage data={data} />;
      case 'family': return filters.family ? <FamilyPage data={data} family={filters.family} onNavExperiment={(eid: string) => navigate('experiment', undefined, eid)} /> : <HomePage data={data} onNav={navigate} />;
      case 'sqp': return <FamilyPage data={data} family={filters.family} onNavExperiment={(eid: string) => navigate('experiment', undefined, eid)} />;
      case 'learn': return <LearnPage data={data} />;
      case 'kwds': return <KeywordsPage data={data} />;
      case 'log': return <LogPage data={data} />;
      case 'health': return <HealthPage data={data} />;
      case 'experiment': return experimentId ? <ExperimentPage data={data} experimentId={experimentId} /> : <HomePage data={data} onNav={navigate} />;
      case 'ads': return <AdsPerformancePage data={data} />;
      case 'strategies': return <StrategiesPage data={data} />;
      case 'admin': return <AdminPage />;
      case 'do': return <DoPage data={data} onNav={navigate} />;
      case 'brand': return <BrandPage data={data} />;
      case 'plan': return <PlanPage data={data} />;
      case 'supply': return <SupplyPage data={data} />;
      case 'alerts': return <AlertsPage />;
      case 'products': return <ProductsPage data={data} />;
      case 'kpi': return <KpiPage data={data} />;
      default: return <HomePage data={data} onNav={navigate} />;
    }
  };

  return (
    <>
      {import.meta.env.DEV && (
        <div className="fixed bottom-2 left-2 z-[100] px-2 py-1 rounded text-[10px] font-mono" title={!fromCube && !data.summary?.length ? 'Run: cd cube && npm run dev' : ''}
          style={{ background: fromCube ? 'rgba(34,197,94,.2)' : 'rgba(234,179,8,.2)', color: fromCube ? '#86efac' : '#fde047' }}>
          Cube: {fromCube ? 'on' : 'off'} | summary: {data.summary?.length ?? 0} | trends: {data.weekly_trends?.length ?? 0}
        </div>
      )}
      <Header data={data} onNav={navigate} />
      <Sidebar activePage={page} activeFamily={filters.family} onNav={navigate} themeMode={themeMode} onToggleTheme={toggleTheme} healthBadge={(() => {
        const meta = data._meta || {};
        const files = meta.files || {};
        const criticalFiles = ['summary.json', 'actions.json', 'products.json', 'weekly_trends.json', 'monthly_trends.json', 'keyword_product_map.json', 'drivers.json'];
        const hasCriticalError = criticalFiles.some(f => files[f]?.status === 'error' || (files[f]?.rows ?? 0) < 1);
        if ((meta.queries_failed ?? 0) > 0 || hasCriticalError) return 'error';
        const hasWarning = Object.values(files).some(f => f?.status === 'error');
        if (hasWarning) return 'warn';
        return 'ok';
      })()} alertBadge={alertBadge} adminBadge={adminBadge} />
      <main className="fixed top-14 left-[72px] right-0 bottom-0 overflow-y-auto px-8 py-5 pb-16 scroll-smooth">
        <FilterBar data={data} page={page} />
        <PageSummaryBar />
        <div key={page} className="animate-in rounded-xl border border-[var(--color-border)] bg-[var(--color-card)] shadow-[var(--shadow-card)] p-6 mt-3">
          {renderPage()}
        </div>
      </main>
    </>
  );
}

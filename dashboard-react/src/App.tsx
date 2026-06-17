import { useState, useCallback, useEffect, lazy, Suspense } from 'react';
import { useUnifiedData } from './hooks/useUnifiedData';
import { CubeDataProvider, useCubeContext } from './hooks/data/CubeDataProvider';
import { useGroundTruth } from './hooks/useGroundTruth';
import { useTheme } from './hooks/useTheme';
import { FiltersProvider, useFilters } from './hooks/useFilters';
import { Header } from './components/Header';
import { Sidebar } from './components/Sidebar';
import { FilterBar } from './components/FilterBar';
import { DashboardSkeleton } from './components/Skeleton';
import { PageSummaryBar, PageSummaryProvider } from './components/PageSummaryBar';
import { DoQueueProvider } from './hooks/useDoQueue';
import { ViewModeProvider, useViewMode, isPageVisible } from './hooks/useViewMode';
import { AuthProvider, useAuth } from './contexts/AuthContext';
import { LoginScreen } from './components/LoginScreen';
import type { PageId, FamilyName } from './types';
import { apiFetch } from './utils/apiFetch';

// Pages are lazy-loaded: the initial bundle ships only the app shell, and each
// page is fetched as its own chunk on first navigation. This keeps first paint
// from downloading + parsing code for all 21 pages (recharts, jspdf, etc.).
const HomePage = lazy(() => import('./pages/HomePage').then(m => ({ default: m.HomePage })));
const ActionsPage = lazy(() => import('./pages/ActionsPage').then(m => ({ default: m.ActionsPage })));
const PeakPage = lazy(() => import('./pages/PeakPage').then(m => ({ default: m.PeakPage })));
const FamilyPage = lazy(() => import('./pages/FamilyPage').then(m => ({ default: m.FamilyPage })));
const LearnPage = lazy(() => import('./pages/LearnPage').then(m => ({ default: m.LearnPage })));
const KeywordsPage = lazy(() => import('./pages/KeywordsPage').then(m => ({ default: m.KeywordsPage })));
const LogPage = lazy(() => import('./pages/LogPage').then(m => ({ default: m.LogPage })));
const HealthPage = lazy(() => import('./pages/HealthPage').then(m => ({ default: m.HealthPage })));
const ExperimentPage = lazy(() => import('./pages/ExperimentPage').then(m => ({ default: m.ExperimentPage })));
const AdsPerformancePage = lazy(() => import('./pages/AdsPerformancePage').then(m => ({ default: m.AdsPerformancePage })));
const StrategiesPage = lazy(() => import('./pages/StrategiesPage').then(m => ({ default: m.StrategiesPage })));
const AdminPage = lazy(() => import('./pages/AdminPage').then(m => ({ default: m.AdminPage })));
const DoPage = lazy(() => import('./pages/DoPage').then(m => ({ default: m.DoPage })));
const BrandPage = lazy(() => import('./pages/BrandPage').then(m => ({ default: m.BrandPage })));
const PlanPage = lazy(() => import('./pages/PlanPage').then(m => ({ default: m.PlanPage })));
const SupplyPage = lazy(() => import('./pages/SupplyPage').then(m => ({ default: m.SupplyPage })));
const AlertsPage = lazy(() => import('./pages/AlertsPage').then(m => ({ default: m.AlertsPage })));
const ProductsPage = lazy(() => import('./pages/ProductsPage').then(m => ({ default: m.ProductsPage })));
const KpiPage = lazy(() => import('./pages/KpiPage').then(m => ({ default: m.KpiPage })));
const ResearchPage = lazy(() => import('./pages/ResearchPage').then(m => ({ default: m.ResearchPage })));

export default function App() {
  return (
    <CubeDataProvider>
      <AuthProvider>
        <DoQueueProvider>
          <ViewModeProvider>
            <FiltersProvider>
              <PageSummaryProvider>
                <AppWrapper />
              </PageSummaryProvider>
            </FiltersProvider>
          </ViewModeProvider>
        </DoQueueProvider>
      </AuthProvider>
    </CubeDataProvider>
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

  const { ensurePage, isPageReady } = useCubeContext();

  const gt = useGroundTruth();
  const { mode: themeMode, toggle: toggleTheme } = useTheme();
  const { filters, setFilter } = useFilters();
  const [page, setPage] = useState<PageId>('home');
  const [experimentId, setExperimentId] = useState<string | null>(null);
  const [alertBadge, setAlertBadge] = useState<{ critical: number; warning: number; total: number } | undefined>();
  const [adminBadge, setAdminBadge] = useState<'error' | 'ok' | null>(null);
  const { mode: viewMode } = useViewMode();

  // In user view, admin-only pages fall back to home (derived, not state —
  // switching back to admin view returns to the original page)
  const visiblePage: PageId = isPageVisible(page, viewMode) ? page : 'home';

  // Load only the datasets the current page needs (+ shell core). Cached, deduped.
  useEffect(() => { ensurePage(visiblePage); }, [visiblePage, ensurePage]);
  const pageReady = isPageReady(visiblePage);

  // Fetch alert count for sidebar badge
  useEffect(() => {
    const fetchCount = () => {
      apiFetch('/api/alerts/count').then(r => r.ok ? r.json() : null).then(d => {
        if (d) setAlertBadge({ critical: d.critical || 0, warning: d.warning || 0, total: d.total || 0 });
      }).catch(() => {});
      
      apiFetch('/api/admin/pipeline-logs').then(r => r.ok ? r.json() : null).then(d => {
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

  if (loading || !pageReady) {
    return (
      <>
        <Header data={data} onNav={navigate} />
        <Sidebar activePage={visiblePage} activeFamily={filters.family} onNav={navigate} themeMode={themeMode} onToggleTheme={toggleTheme} />
        <main className="fixed top-14 left-[72px] right-0 bottom-0 overflow-y-auto px-8 py-5 pb-16 scroll-smooth">
          <FilterBar data={data} page={page} />
          <DashboardSkeleton />
        </main>
      </>
    );
  }

  const renderPage = () => {
    switch (visiblePage) {
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
      case 'research': return <ResearchPage />;
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
      <Sidebar activePage={visiblePage} activeFamily={filters.family} onNav={navigate} themeMode={themeMode} onToggleTheme={toggleTheme} healthBadge={(() => {
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
          <Suspense fallback={<div className="flex items-center justify-center py-24 text-sm text-[var(--color-muted)]">Loading…</div>}>
            {renderPage()}
          </Suspense>
        </div>
      </main>
    </>
  );
}

import { Home, Zap, Mountain, BarChart2, Search, GraduationCap, ClipboardList, HeartPulse, Target, Megaphone, Settings, Sun, Moon, CheckSquare, Shield, Calculator, Package, Bell, Rocket, LayoutDashboard, TrendingUp, Eye, EyeOff, CalendarClock } from 'lucide-react';
import { useViewMode, isPageVisible } from '../hooks/useViewMode';
import type { PageId, FamilyName } from '../types';

interface NavItem {
  page: PageId;
  family?: FamilyName;
  icon: React.ReactNode;
  label: string;
}

interface NavGroup {
  header: string;
  items: NavItem[];
}

const NAV_GROUPS: NavGroup[] = [
  {
    header: 'Overview',
    items: [
      { page: 'home', icon: <Home size={16} />, label: 'HOME' },
      { page: 'thisweek', icon: <CalendarClock size={16} />, label: 'THIS WEEK' },
      { page: 'actions', icon: <Zap size={16} />, label: 'ACTIONS' },
      { page: 'do', icon: <CheckSquare size={16} />, label: 'DO' },
      { page: 'peak', icon: <Mountain size={16} />, label: 'PEAK' },
      { page: 'ads', icon: <Megaphone size={16} />, label: 'ADS' },
      { page: 'strategies', icon: <Target size={16} />, label: 'STRATEGY' },
      { page: 'brand', icon: <Shield size={16} />, label: 'BRAND' },
      { page: 'plan', icon: <Calculator size={16} />, label: 'PLAN' },
      { page: 'supply', icon: <Package size={16} />, label: 'SUPPLY' },
      { page: 'products', icon: <Rocket size={16} />, label: 'PRODUCTS' },
      { page: 'alerts', icon: <Bell size={16} />, label: 'ALERTS' },
      { page: 'kpi', icon: <LayoutDashboard size={16} />, label: 'KPI' },
    ],
  },
  {
    header: 'Data',
    items: [
      { page: 'sqp', icon: <BarChart2 size={16} />, label: 'SQP' },
      { page: 'learn', icon: <GraduationCap size={16} />, label: 'LEARN' },
      { page: 'kwds', icon: <Search size={16} />, label: 'KEYWORDS' },
      { page: 'research', icon: <TrendingUp size={16} />, label: 'RESEARCH' },
      { page: 'log', icon: <ClipboardList size={16} />, label: 'LOG' },
    ],
  },
  {
    header: 'System',
    items: [
      { page: 'health', icon: <HeartPulse size={16} />, label: 'HEALTH' },
      { page: 'admin', icon: <Settings size={16} />, label: 'ADMIN' },
    ],
  },
];

export function Sidebar({ activePage, activeFamily, onNav, themeMode, onToggleTheme, healthBadge, alertBadge, adminBadge }: {
  activePage: PageId;
  activeFamily: FamilyName | null;
  onNav: (page: PageId, family?: FamilyName) => void;
  themeMode?: 'dark' | 'light';
  onToggleTheme?: () => void;
  healthBadge?: 'ok' | 'warn' | 'error';
  alertBadge?: { critical: number; warning: number; total: number };
  adminBadge?: 'error' | 'ok' | null;
}) {
  const { mode: viewMode, isAdmin, toggle: toggleViewMode } = useViewMode();
  const visibleGroups = NAV_GROUPS
    .map(g => ({ ...g, items: g.items.filter(i => isPageVisible(i.page, viewMode)) }))
    .filter(g => g.items.length > 0);

  return (
    <nav className="fixed top-14 left-0 bottom-0 w-[72px] bg-surface/70 backdrop-blur-xl border-r border-border flex flex-col py-1 z-40 overflow-y-auto">
      {visibleGroups.map((group, gi) => (
        <div key={gi}>
          {gi > 0 && <div className="h-px bg-border mx-3 my-1" />}
          <div className="text-[7px] uppercase font-bold tracking-[0.12em] text-faint/40 text-center py-1 select-none">
            {group.header}
          </div>
          {group.items.map((item, ii) => {
            const isActive = item.page === activePage && (!item.family || item.family === activeFamily);
            return (
              <button
                key={ii}
                onClick={() => onNav(item.page, item.family)}
                className={`flex flex-col items-center justify-center w-[58px] mx-auto py-2 text-[9px] font-semibold uppercase tracking-wide rounded-lg cursor-pointer transition-all duration-200 ${
                  isActive
                    ? 'text-blue-400 bg-blue-500/10'
                    : 'text-muted hover:text-subtle hover:bg-white/[.04]'
                }`}
              >
                <span className="mb-1 relative">
                  {item.icon}
                  {item.page === 'health' && healthBadge && healthBadge !== 'ok' && (
                    <span className={`absolute -top-1 -right-1.5 w-2.5 h-2.5 rounded-full border-2 border-surface/70 animate-pulse ${healthBadge === 'error' ? 'bg-red-500' : 'bg-amber-500'}`} />
                  )}
                  {item.page === 'admin' && adminBadge === 'error' && (
                    <span className="absolute -top-1 -right-1.5 w-2.5 h-2.5 rounded-full border-2 border-surface/70 bg-red-500 animate-pulse" />
                  )}
                  {item.page === 'alerts' && alertBadge && alertBadge.total > 0 && (
                    <span className={`absolute -top-1.5 -right-2 min-w-[16px] h-4 flex items-center justify-center rounded-full text-[8px] font-bold text-white border border-surface/70 px-0.5 ${
                      alertBadge.critical > 0 ? 'bg-red-500 animate-pulse' : 'bg-amber-500'
                    }`}>
                      {alertBadge.total}
                    </span>
                  )}
                </span>
                <span className="leading-none">{item.label}</span>
              </button>
            );
          })}
        </div>
      ))}

      <div className="flex-1" />
      <div className="h-px bg-border mx-3 my-1" />
      <button
        onClick={toggleViewMode}
        className="flex flex-col items-center justify-center w-[58px] mx-auto py-2 text-[8px] font-semibold uppercase tracking-widest text-faint hover:text-muted transition-all duration-300"
        title={isAdmin ? 'Admin view: all pages & diagnostics. Click for simple view.' : 'Simple view: curated pages only. Click for admin view.'}
      >
        {isAdmin
          ? <Eye size={14} className="mb-1 text-violet-400" />
          : <EyeOff size={14} className="mb-1 text-faint" />
        }
        <span className="leading-none">{isAdmin ? 'ADMIN' : 'SIMPLE'}</span>
      </button>
      {onToggleTheme && (
        <>
          <button
            onClick={onToggleTheme}
            className="flex flex-col items-center justify-center w-[58px] mx-auto py-2 text-[8px] font-semibold uppercase tracking-widest text-faint hover:text-muted transition-all duration-300"
            title={themeMode === 'dark' ? 'Switch to Light mode' : 'Switch to Dark mode'}
          >
            {themeMode === 'dark'
              ? <Sun size={14} className="mb-1 text-amber-400" />
              : <Moon size={14} className="mb-1 text-blue-400" />
            }
            <span className="leading-none">{themeMode === 'dark' ? 'LIGHT' : 'DARK'}</span>
          </button>
        </>
      )}
    </nav>
  );
}


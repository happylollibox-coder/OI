import { useState, useEffect, useCallback } from 'react';

const STORAGE_KEY = 'oi-theme';

export type ThemeMode = 'dark' | 'light';

export function useTheme() {
  const [mode, setMode] = useState<ThemeMode>(() => {
    try { return (localStorage.getItem(STORAGE_KEY) as ThemeMode) || 'light'; }
    catch { return 'light'; }
  });

  useEffect(() => {
    const root = document.documentElement;
    root.classList.remove('light-mode');
    if (mode === 'light') root.classList.add('light-mode');
    try { localStorage.setItem(STORAGE_KEY, mode); }
    catch { /* noop */ }
  }, [mode]);

  const toggle = useCallback(() =>
    setMode(m => m === 'dark' ? 'light' : 'dark'), []);

  return { mode, toggle };
}

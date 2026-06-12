import React, { createContext, useContext, useState } from 'react';
import { jwtDecode } from 'jwt-decode';

interface AuthContextType {
  token: string | null;
  isAuthenticated: boolean;
  userEmail: string | null;
  handleLoginSuccess: (token: string) => void;
  logout: () => void;
  loading: boolean;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

// Dev bypass: only in dev builds AND on localhost — a production bundle must
// never self-authenticate, even if someone serves it from localhost.
const IS_LOCAL = import.meta.env.DEV &&
  (window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1');
// This is a valid JWT signed with 'dev-secret-key-123' (the local-dev Cube secret);
// it expires in the year 9999 and is only ever used for IS_LOCAL dev sessions.
const LOCAL_DEV_TOKEN = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJlbWFpbCI6ImxvY2FsQGRldiIsImV4cCI6MjUzNDAyMzAwNzk5fQ.prA2to8zmwnX0r9FhPZ5mOL_-WqyBozHL1LpuoH2gJc';
const DEV_TOKEN = import.meta.env.VITE_DEV_BYPASS_TOKEN || '';

/** Check if a JWT token is still valid (not expired). */
function isTokenValid(t: string): boolean {
  try {
    const decoded = jwtDecode<{ exp?: number }>(t);
    if (!decoded.exp) return false;
    // Allow 60s buffer for clock skew
    return decoded.exp * 1000 > Date.now() - 60_000;
  } catch {
    return false;
  }
}

function decodeEmail(t: string): string | null {
  try { return jwtDecode<{ email?: string }>(t).email ?? null; } catch { return null; }
}

interface AuthState { token: string | null; email: string | null }

/** Resolve the initial auth state synchronously (lazy useState initializer). */
function initialAuthState(): AuthState {
  // 1. Check URL parameters for a new token (redirected from Flask)
  const params = new URLSearchParams(window.location.search);
  const urlToken = params.get('token');
  if (urlToken && isTokenValid(urlToken)) {
    localStorage.setItem('dashboard_token', urlToken);
    // Clean up URL
    window.history.replaceState({}, document.title, window.location.pathname);
    return { token: urlToken, email: decodeEmail(urlToken) };
  }

  // 2. Check local storage — but validate the token is not expired
  const storedToken = localStorage.getItem('dashboard_token');
  if (storedToken && isTokenValid(storedToken)) {
    return { token: storedToken, email: decodeEmail(storedToken) };
  }
  // Token expired or missing — clear it
  localStorage.removeItem('dashboard_token');

  // 3. Fallback to dev token in development (via env)
  if (import.meta.env.DEV && DEV_TOKEN) {
    localStorage.setItem('dashboard_token', DEV_TOKEN);
    return { token: DEV_TOKEN, email: decodeEmail(DEV_TOKEN) };
  }
  // 4. Automatic local bypass (dev builds only)
  if (IS_LOCAL) {
    localStorage.setItem('dashboard_token', LOCAL_DEV_TOKEN);
    return { token: LOCAL_DEV_TOKEN, email: decodeEmail(LOCAL_DEV_TOKEN) };
  }
  return { token: null, email: null };
}

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [auth, setAuth] = useState<AuthState>(initialAuthState);

  const handleLoginSuccess = (newToken: string) => {
    localStorage.setItem('dashboard_token', newToken);
    setAuth({ token: newToken, email: decodeEmail(newToken) });
  };

  const logout = () => {
    localStorage.removeItem('dashboard_token');
    setAuth({ token: null, email: null });
  };

  const value = {
    token: auth.token,
    isAuthenticated: !!auth.token,
    userEmail: auth.email,
    handleLoginSuccess,
    logout,
    loading: false, // auth resolves synchronously at mount
  };

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
}

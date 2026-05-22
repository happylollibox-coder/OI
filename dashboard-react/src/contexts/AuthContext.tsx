import React, { createContext, useContext, useEffect, useState } from 'react';
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

// Dev bypass: If running on localhost, use an auto-generated token to bypass login
const IS_LOCAL = window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1';
// This is a valid JWT signed with 'dev-secret-key-123' that expires in the year 9999
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

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [token, setToken] = useState<string | null>(null);
  const [userEmail, setUserEmail] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    // 1. Check URL parameters for a new token (redirected from Flask)
    const params = new URLSearchParams(window.location.search);
    const urlToken = params.get('token');

    if (urlToken && isTokenValid(urlToken)) {
      localStorage.setItem('dashboard_token', urlToken);
      setToken(urlToken);
      try { setUserEmail((jwtDecode<any>(urlToken)).email ?? null); } catch { /* noop */ }
      // Clean up URL
      window.history.replaceState({}, document.title, window.location.pathname);
    } else {
      // 2. Check local storage — but validate the token is not expired
      const storedToken = localStorage.getItem('dashboard_token');
      if (storedToken && isTokenValid(storedToken)) {
        setToken(storedToken);
        try { setUserEmail((jwtDecode<any>(storedToken)).email ?? null); } catch { /* noop */ }
      } else {
        // Token expired or missing — clear it
        localStorage.removeItem('dashboard_token');

        if (import.meta.env.DEV && DEV_TOKEN) {
          // 3. Fallback to dev token in development (via env)
          localStorage.setItem('dashboard_token', DEV_TOKEN);
          setToken(DEV_TOKEN);
        } else if (IS_LOCAL) {
          // 4. Automatic local bypass
          localStorage.setItem('dashboard_token', LOCAL_DEV_TOKEN);
          setToken(LOCAL_DEV_TOKEN);
        }
      }
    }
    setLoading(false);
  }, []);

  const handleLoginSuccess = (newToken: string) => {
    localStorage.setItem('dashboard_token', newToken);
    setToken(newToken);
    try { setUserEmail((jwtDecode<any>(newToken)).email ?? null); } catch { /* noop */ }
  };

  const logout = () => {
    localStorage.removeItem('dashboard_token');
    setToken(null);
    setUserEmail(null);
  };

  const value = {
    token,
    isAuthenticated: !!token,
    userEmail,
    handleLoginSuccess,
    logout,
    loading
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

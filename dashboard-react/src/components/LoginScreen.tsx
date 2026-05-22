import React from 'react';
import { useAuth } from '../contexts/AuthContext';
import { Lock } from 'lucide-react';
import { GoogleLogin } from '@react-oauth/google';
import { jwtDecode } from 'jwt-decode';

const ALLOWED_USERS = [
  'happylollibox@gmail.com',
  'adva.tal2@gmail.com'
];

export function LoginScreen() {
  const { handleLoginSuccess, loading } = useAuth();

  if (loading) {
    return (
      <div className="flex h-screen w-screen items-center justify-center bg-[var(--color-bg)]">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-green-500"></div>
      </div>
    );
  }

  return (
    <div className="flex h-screen w-screen items-center justify-center bg-[var(--color-bg)] relative overflow-hidden">
      {/* Decorative background elements */}
      <div className="absolute top-[-10%] left-[-10%] w-[40%] h-[40%] rounded-full bg-green-500/10 blur-[120px]"></div>
      <div className="absolute bottom-[-10%] right-[-10%] w-[40%] h-[40%] rounded-full bg-blue-500/10 blur-[120px]"></div>
      
      <div className="relative z-10 w-full max-w-md p-8 rounded-2xl border border-[var(--color-border)] bg-[var(--color-card)]/80 backdrop-blur-xl shadow-2xl">
        <div className="flex flex-col items-center text-center space-y-6">
          <div className="w-16 h-16 rounded-full bg-green-500/20 flex items-center justify-center border border-green-500/30">
            <Lock className="w-8 h-8 text-green-400" />
          </div>
          
          <div className="space-y-2">
            <h1 className="text-2xl font-bold text-white tracking-tight">Ori Intelligence</h1>
            <p className="text-[var(--color-text-muted)] text-sm px-4">
              Secure analytics dashboard. Please sign in through the centralized Data Entry system.
            </p>
          </div>
          
          <div className="w-full flex justify-center py-2">
            <GoogleLogin
              onSuccess={(credentialResponse) => {
                if (credentialResponse.credential) {
                  // Decode token to verify email before setting it
                  try {
                    const decoded = jwtDecode(credentialResponse.credential) as any;
                    if (decoded.email && ALLOWED_USERS.includes(decoded.email)) {
                      handleLoginSuccess(credentialResponse.credential);
                    } else {
                      alert(`Access denied. Your email (${decoded.email}) is not authorized.`);
                      console.error('Unauthorized email:', decoded.email);
                    }
                  } catch (e) {
                    console.error('Invalid token', e);
                  }
                }
              }}
              onError={() => {
                console.error('Login Failed');
              }}
              theme="filled_black"
              shape="rectangular"
              size="large"
              text="signin_with"
            />
          </div>

          <p className="text-xs text-[var(--color-text-muted)] mt-8">
            Access requires authorization on the Admin Console.
          </p>
        </div>
      </div>
    </div>
  );
}

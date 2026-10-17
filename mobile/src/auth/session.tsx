import * as LocalAuthentication from 'expo-local-authentication';
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { AppState, Platform } from 'react-native';

import { api, ApiError, loadSession, onApiEvent, saveRegion, saveSession, type Session } from '@/api/client';
import { getItem, installId, KEYS, setItem } from '@/auth/storage';
import { APP_VERSION } from '@/api/config';

/**
 * Who is signed in, and the steps to get there (proposal Workflow Journey, Part A):
 *   region → email + password → (code, when two-factor is on) → signed in → (Face ID lock)
 *
 * The server owns every rule (lockout, two-factor, investor-only); this only moves between the
 * screens and keeps the tokens in secure storage.
 */
export type AuthStatus = 'loading' | 'needsRegion' | 'signedOut' | 'code' | 'signedIn' | 'locked' | 'updateRequired';

type Challenge = { challenge: string; method: string; attemptsLeft: number };

type AuthContextValue = {
  status: AuthStatus;
  challenge: Challenge | null;
  biometricEnabled: boolean;
  chooseRegion: (code: string) => Promise<void>;
  changeRegion: () => Promise<void>;
  signIn: (email: string, password: string) => Promise<void>;
  verifyCode: (code: string) => Promise<void>;
  resendCode: () => Promise<void>;
  signOut: () => Promise<void>;
  unlock: () => Promise<boolean>;
  setBiometric: (on: boolean) => Promise<void>;
};

const AuthContext = createContext<AuthContextValue | null>(null);

/** Reopening after this long in the background asks for Face ID / fingerprint (E32) */
const LOCK_AFTER_MS = 5 * 60 * 1000;
/** After this many failed biometric attempts, sign in again with the password (E31) */
const MAX_BIOMETRIC_FAILURES = 3;

type TokenResponse = { access_token: string; refresh_token: string; device_id: number };

async function deviceAttrs() {
  const name = Platform.OS === 'web' ? 'Web browser' : (await import('expo-device')).deviceName ?? Platform.OS;
  return { install_id: await installId(), platform: Platform.OS === 'android' ? 'android' : 'ios', name, app_version: APP_VERSION };
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [status, setStatus] = useState<AuthStatus>('loading');
  const [challenge, setChallenge] = useState<Challenge | null>(null);
  const [biometricEnabled, setBiometricEnabled] = useState(false);
  const backgroundedAt = useRef<number | null>(null);
  const biometricFailures = useRef(0);

  // Restore on launch
  useEffect(() => {
    (async () => {
      const { regionCode, session } = await loadSession();
      const bio = (await getItem(KEYS.biometric)) === 'on';
      setBiometricEnabled(bio);
      if (!regionCode) return setStatus('needsRegion');
      if (!session) return setStatus('signedOut');
      setStatus(bio ? 'locked' : 'signedIn');
    })();
  }, []);

  // Session ended on the server (signed out on the website, password changed) or app too old
  useEffect(() => {
    const off = onApiEvent((event) => setStatus(event === 'updateRequired' ? 'updateRequired' : 'signedOut'));
    return () => { off(); };
  }, []);

  // E32 — lock after 5 minutes in the background
  useEffect(() => {
    const sub = AppState.addEventListener('change', (next) => {
      if (next === 'background') backgroundedAt.current = Date.now();
      if (next === 'active' && backgroundedAt.current && biometricEnabled && status === 'signedIn' &&
          Date.now() - backgroundedAt.current > LOCK_AFTER_MS) {
        setStatus('locked');
      }
      if (next === 'active') backgroundedAt.current = null;
    });
    return () => sub.remove();
  }, [biometricEnabled, status]);

  const finishSignIn = useCallback(async (tokens: TokenResponse) => {
    const session: Session = { accessToken: tokens.access_token, refreshToken: tokens.refresh_token, deviceId: tokens.device_id };
    await saveSession(session);
    setChallenge(null);
    setStatus('signedIn');
  }, []);

  const chooseRegion = useCallback(async (code: string) => {
    await saveRegion(code);
    setStatus('signedOut');
  }, []);

  const signOut = useCallback(async () => {
    // Ends this phone's session on the server and stops its pushes (proposal C4)
    try {
      await api('/api/mobile/v1/session', { method: 'DELETE', retry: false });
    } catch {
      // already signed out server-side — nothing more to do
    }
    await saveSession(null);
    setStatus('signedOut');
  }, []);

  const changeRegion = useCallback(async () => {
    await signOut();
    await saveRegion(null);
    setStatus('needsRegion');
  }, [signOut]);

  const signIn = useCallback(async (email: string, password: string) => {
    const response = await api<TokenResponse & { challenge?: string; method?: string; attempts_left?: number }>(
      '/api/mobile/v1/session',
      { method: 'POST', auth: false, body: { email: email.trim(), password, device: await deviceAttrs() } },
    );
    if (response.challenge) {
      setChallenge({ challenge: response.challenge, method: response.method ?? 'authenticator', attemptsLeft: response.attempts_left ?? 3 });
      setStatus('code');
      return;
    }
    await finishSignIn(response);
  }, [finishSignIn]);

  const verifyCode = useCallback(async (code: string) => {
    if (!challenge) return;
    try {
      const tokens = await api<TokenResponse>('/api/mobile/v1/session/verify', {
        method: 'POST', auth: false, body: { challenge: challenge.challenge, code: code.replace(/\s+/g, ''), device: await deviceAttrs() },
      });
      await finishSignIn(tokens);
    } catch (error) {
      if (error instanceof ApiError && error.code === 'invalid_code') {
        setChallenge({ ...challenge, attemptsLeft: Number(error.body.attempts_left ?? challenge.attemptsLeft - 1) });
      } else if (error instanceof ApiError && error.status === 401) {
        // Too many attempts / timed out — back to the password screen, with the reason
        setChallenge(null);
        setStatus('signedOut');
      }
      throw error;
    }
  }, [challenge, finishSignIn]);

  const resendCode = useCallback(async () => {
    if (!challenge) return;
    await api('/api/mobile/v1/session/resend', { method: 'POST', auth: false, body: { challenge: challenge.challenge } });
  }, [challenge]);

  const unlock = useCallback(async () => {
    const result = await LocalAuthentication.authenticateAsync({ promptMessage: 'Unlock CapHive', disableDeviceFallback: false });
    if (result.success) {
      biometricFailures.current = 0;
      setStatus('signedIn');
      return true;
    }
    biometricFailures.current += 1;
    if (biometricFailures.current >= MAX_BIOMETRIC_FAILURES) {
      biometricFailures.current = 0;
      await signOut();
    }
    return false;
  }, [signOut]);

  const setBiometric = useCallback(async (on: boolean) => {
    await setItem(KEYS.biometric, on ? 'on' : null);
    setBiometricEnabled(on);
  }, []);

  const value = useMemo(
    () => ({ status, challenge, biometricEnabled, chooseRegion, changeRegion, signIn, verifyCode, resendCode, signOut, unlock, setBiometric }),
    [status, challenge, biometricEnabled, chooseRegion, changeRegion, signIn, verifyCode, resendCode, signOut, unlock, setBiometric],
  );
  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth outside AuthProvider');
  return ctx;
}

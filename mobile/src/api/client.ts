import { APP_VERSION, regionFor } from '@/api/config';
import { getItem, KEYS, setItem } from '@/auth/storage';

/**
 * The one way the app talks to CapHive (LLD "Mobile App Build Detail"): the region's base URL,
 * the phone's bearer token, X-App-Version and the phone's language. The same token works on the
 * mobile endpoints (/api/mobile/v1/*) and on the website's own .json endpoints, which the app
 * reuses wherever they exist.
 *
 * On 401 it refreshes the token pair once (shared by concurrent requests) and retries; if that
 * fails the session has ended (signed out on the website, password changed…) and the app returns
 * to sign-in. On 426 the app must be updated.
 */
export type Session = { accessToken: string; refreshToken: string; deviceId: number };

export class ApiError extends Error {
  constructor(public status: number, public code: string, message: string, public body: Record<string, unknown> = {}) {
    super(message);
  }
}

type Listener = (event: 'signedOut' | 'updateRequired') => void;
const listeners = new Set<Listener>();
export function onApiEvent(listener: Listener) {
  listeners.add(listener);
  return () => listeners.delete(listener);
}
const emit = (event: 'signedOut' | 'updateRequired') => listeners.forEach((l) => l(event));

let session: Session | null = null;
let regionCode: string | null = null;
let refreshing: Promise<boolean> | null = null;

export async function loadSession() {
  regionCode = await getItem(KEYS.region);
  const raw = await getItem(KEYS.session);
  session = raw ? (JSON.parse(raw) as Session) : null;
  return { regionCode, session };
}

export async function saveSession(next: Session | null) {
  session = next;
  await setItem(KEYS.session, next ? JSON.stringify(next) : null);
}

export async function saveRegion(code: string | null) {
  regionCode = code;
  await setItem(KEYS.region, code);
}

export function currentRegion() {
  return regionFor(regionCode);
}

export function baseUrl(): string {
  const region = currentRegion();
  if (!region) throw new ApiError(0, 'no_region', 'Choose your region first.');
  return region.url;
}

function language(): string {
  try {
    return Intl.DateTimeFormat().resolvedOptions().locale || 'en-IN';
  } catch {
    return 'en-IN';
  }
}

type Options = { method?: string; body?: unknown; auth?: boolean; retry?: boolean };

export async function api<T = unknown>(path: string, { method = 'GET', body, auth = true, retry = true }: Options = {}): Promise<T> {
  const headers: Record<string, string> = {
    Accept: 'application/json',
    'Content-Type': 'application/json',
    'X-App-Version': APP_VERSION,
    'Accept-Language': language(),
  };
  if (auth && session) headers.Authorization = `Bearer ${session.accessToken}`;

  let response: Response;
  try {
    response = await fetch(`${baseUrl()}${path}`, { method, headers, body: body == null ? undefined : JSON.stringify(body) });
  } catch {
    throw new ApiError(0, 'offline', "You're offline. Check your connection and try again.");
  }

  // Forced update (spec "Forced update", X21)
  if (response.status === 426) {
    emit('updateRequired');
    throw new ApiError(426, 'update_required', 'Please update CapHive to continue.');
  }

  // Expired access token → refresh once, then retry; a refused refresh means signed out (X15)
  if (response.status === 401 && auth && session) {
    if (retry && (await refreshOnce())) return api<T>(path, { method, body, auth, retry: false });
    await saveSession(null);
    emit('signedOut');
    throw new ApiError(401, 'unauthorised', 'Please sign in again.');
  }

  if (response.status === 204) return undefined as T;
  const json = (await response.json().catch(() => ({}))) as Record<string, unknown>;
  if (!response.ok) {
    const code = (json.error as string) ?? `http_${response.status}`;
    // The website's own endpoints answer a denied record with 403 "Access Denied"; the app's say 404
    const message = response.status === 403 || response.status === 404
      ? 'You no longer have access to this item.'
      : (json.message as string) ?? 'Something went wrong. Please try again.';
    throw new ApiError(response.status, code, message, json);
  }
  return json as T;
}

function refreshOnce(): Promise<boolean> {
  if (!refreshing) {
    refreshing = (async () => {
      try {
        const tokens = await api<{ access_token: string; refresh_token: string; device_id: number }>(
          '/api/mobile/v1/session/refresh',
          { method: 'POST', body: { refresh_token: session?.refreshToken }, auth: false, retry: false },
        );
        await saveSession({ accessToken: tokens.access_token, refreshToken: tokens.refresh_token, deviceId: tokens.device_id });
        return true;
      } catch {
        return false;
      } finally {
        refreshing = null;
      }
    })();
  }
  return refreshing;
}

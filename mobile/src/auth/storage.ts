import * as SecureStore from 'expo-secure-store';
import { Platform } from 'react-native';

/**
 * Where the session lives: the iOS Keychain / Android Keystore via expo-secure-store, readable
 * only while the phone is unlocked and never backed up to another device (LLD "Security Review").
 * The web review build has no keychain, so it falls back to sessionStorage (cleared with the tab).
 */
const OPTIONS: SecureStore.SecureStoreOptions = {
  keychainAccessible: SecureStore.WHEN_UNLOCKED_THIS_DEVICE_ONLY,
};

const web = Platform.OS === 'web';

export async function getItem(key: string): Promise<string | null> {
  if (web) return globalThis.sessionStorage?.getItem(key) ?? null;
  return SecureStore.getItemAsync(key, OPTIONS);
}

export async function setItem(key: string, value: string | null): Promise<void> {
  if (web) {
    if (value == null) globalThis.sessionStorage?.removeItem(key);
    else globalThis.sessionStorage?.setItem(key, value);
    return;
  }
  if (value == null) await SecureStore.deleteItemAsync(key, OPTIONS);
  else await SecureStore.setItemAsync(key, value, OPTIONS);
}

export const KEYS = {
  // The site (environment + region) the app is on — JSON of config.Site
  site: 'caphive.site',
  // The sites this phone holds a session for — JSON array of base URLs (lp-mobile-multi-site ②)
  sessionSites: 'caphive.session_sites',
  installId: 'caphive.install_id',
  biometric: 'caphive.biometric',
} as const;

/** Secure-store keys allow only letters, digits, ".", "-" and "_", so a URL is folded into that */
function siteKey(prefix: string, url: string) {
  return `${prefix}.${url.replace(/^https?:\/\//, '').replace(/[^A-Za-z0-9._-]/g, '_')}`;
}

/** One session per site: switching region keeps the other region signed in, as the website does */
export const sessionKey = (url: string) => siteKey('caphive.session', url);

/** The fund manager picked on a site (lp-mobile-multi-site design card ③) */
export const fundManagerKey = (url: string) => siteKey('caphive.fund_manager', url);

/** Generated once per install and kept in secure storage, so a re-sign-in reuses the device row */
export async function installId(): Promise<string> {
  const existing = await getItem(KEYS.installId);
  if (existing) return existing;
  const id = globalThis.crypto?.randomUUID?.() ?? `${Date.now()}-${Math.random().toString(36).slice(2)}`;
  await setItem(KEYS.installId, id);
  return id;
}

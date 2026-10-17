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
  region: 'caphive.region',
  session: 'caphive.session',
  installId: 'caphive.install_id',
  biometric: 'caphive.biometric',
} as const;

/** Generated once per install and kept in secure storage, so a re-sign-in reuses the device row */
export async function installId(): Promise<string> {
  const existing = await getItem(KEYS.installId);
  if (existing) return existing;
  const id = globalThis.crypto?.randomUUID?.() ?? `${Date.now()}-${Math.random().toString(36).slice(2)}`;
  await setItem(KEYS.installId, id);
  return id;
}

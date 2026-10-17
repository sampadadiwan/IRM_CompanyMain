import Constants from 'expo-constants';

/**
 * The CapHive regions this build can sign in to. India and US are independent deployments with
 * their own accounts and data (proposal "Region choice"); the user picks one and the app holds a
 * session for that region only.
 *
 * Set per EAS profile in app.config.ts → `extra.regions`. For local development and the web
 * review build, EXPO_PUBLIC_API_URL points both regions at a local Rails server.
 */
export type Region = { code: 'IN' | 'US'; label: string; url: string };

const local = process.env.EXPO_PUBLIC_API_URL;
const configured = (Constants.expoConfig?.extra?.regions ?? null) as Region[] | null;

export const REGIONS: Region[] = configured ?? [
  { code: 'IN', label: 'India', url: local ?? 'https://app.caphive.com' },
  { code: 'US', label: 'United States', url: local ?? 'https://us.caphive.com' },
];

export function regionFor(code: string | null | undefined): Region | undefined {
  return REGIONS.find((r) => r.code === code);
}

/** Sent as X-App-Version so the server can require an update (spec "Forced update") */
export const APP_VERSION: string = Constants.expoConfig?.version ?? '1.0.0';

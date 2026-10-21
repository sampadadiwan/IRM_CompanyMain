import Constants from 'expo-constants';

/**
 * One app for every CapHive environment and region (openspec/changes/lp-mobile-multi-site,
 * design card ①).
 *
 * The app knows ONE address per environment. After an environment is picked it asks that address
 * which regions exist (GET /api/mobile/v1/sites, the server's own SITES), so the region list
 * always matches what the website's region switcher offers, and staging never lists a production
 * site. `fallbackSites` is used only when that call cannot be answered — an older server that has
 * no /sites yet — so the app still works against it.
 *
 * Only Production is shown to investors. Staging and a typed-in address (a laptop) are revealed by
 * a long press on the CapHive name on the site screen; a staging build starts with them revealed.
 */
export type Region = { code: string; label: string; url: string };

export type EnvironmentId = 'production' | 'staging' | 'custom';

export type Environment = { id: EnvironmentId; label: string; url: string; fallbackSites: Region[] };

export const ENVIRONMENTS: Environment[] = [
  {
    id: 'production', label: 'CapHive', url: 'https://app.caphive.com',
    fallbackSites: [
      { code: 'IN', label: 'India', url: 'https://app.caphive.com' },
      { code: 'US', label: 'US', url: 'https://app.caphive.us' },
    ],
  },
  {
    id: 'staging', label: 'Staging', url: 'https://dev.altconnects.com',
    fallbackSites: [
      { code: 'IN', label: 'India', url: 'https://dev.altconnects.com' },
      { code: 'US', label: 'US', url: 'https://dev.altconnects.us' },
    ],
  },
];

/** A custom environment: one typed-in address (a laptop on the same Wi-Fi), no fallback list */
export function customEnvironment(url: string): Environment {
  return { id: 'custom', label: 'Custom', url: url.trim().replace(/\/+$/, ''), fallbackSites: [] };
}

/** The signed-in place: an environment and one of its regions */
export type Site = Region & { env: EnvironmentId };

const extra = (Constants.expoConfig?.extra ?? {}) as { defaultEnvironment?: EnvironmentId };

/** Which environment the site screen opens on (a staging build opens on Staging) */
export const DEFAULT_ENVIRONMENT: EnvironmentId = extra.defaultEnvironment ?? 'production';

/** Whether the test environments start revealed (any non-production build) */
export const SHOW_TEST_ENVIRONMENTS = DEFAULT_ENVIRONMENT !== 'production';

/** Pre-filled custom address for a development build */
export const DEV_API_URL: string | undefined = process.env.EXPO_PUBLIC_API_URL;

/** Sent as X-App-Version so the server can require an update (spec "Forced update") */
export const APP_VERSION: string = Constants.expoConfig?.version ?? '1.0.0';

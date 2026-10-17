/**
 * Per-build configuration on top of app.json (lp-mobile-app LLD "Configuration and Rollout").
 * Plain JavaScript (not .ts): EAS CLI loads this with Node, which does not run TypeScript here.
 *
 * APP_ENV picks the CapHive sites the build signs in to. India and US are independent
 * deployments — the app holds a session for one at a time — so each build carries both, and the
 * user chooses on first launch. Links into the app use the caphive:// scheme (push notifications);
 * no https universal links in v1 — nothing opens the app from a web link.
 *   development  → a Rails server on this laptop (EXPO_PUBLIC_API_URL in .env.local)
 *   staging      → dev.altconnects.com / dev.altconnects.us
 *   production   → app.caphive.com / app.caphive.us
 */
const SITES = {
  development: {
    IN: process.env.EXPO_PUBLIC_API_URL ?? 'http://localhost:3000',
    US: process.env.EXPO_PUBLIC_API_URL ?? 'http://localhost:3000',
  },
  staging: { IN: 'https://dev.altconnects.com', US: 'https://dev.altconnects.us' },
  production: { IN: 'https://app.caphive.com', US: 'https://app.caphive.us' },
};

module.exports = ({ config }) => {
  const env = process.env.APP_ENV ?? 'development';
  const sites = SITES[env] ?? SITES.development;

  return {
    ...config,
    owner: 'caphive',
    name: env === 'production' ? 'CapHive' : `CapHive (${env})`,
    slug: config.slug ?? 'caphive-lp',
    ios: {
      ...config.ios,
      bundleIdentifier: env === 'production' ? 'com.caphive.lp' : `com.caphive.lp.${env}`,
    },
    android: {
      ...config.android,
      package: env === 'production' ? 'com.caphive.lp' : `com.caphive.lp.${env}`,
    },
    extra: {
      ...config.extra,
      appEnv: env,
      regions: [
        { code: 'IN', label: 'India', url: sites.IN },
        { code: 'US', label: 'United States', url: sites.US },
      ],
      eas: { projectId: process.env.EAS_PROJECT_ID ?? config.extra?.eas?.projectId },
    },
  };
};

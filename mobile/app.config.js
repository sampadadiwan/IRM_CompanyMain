/**
 * Per-build configuration on top of app.json (lp-mobile-app LLD "Configuration and Rollout").
 * Plain JavaScript (not .ts): EAS CLI loads this with Node, which does not run TypeScript here.
 *
 * ONE app for every environment (openspec/changes/lp-mobile-multi-site, design card ①): the
 * server addresses are no longer baked into a build. Every build carries the same environment list
 * (src/api/config.ts) and the user picks a site on first launch. APP_ENV only decides
 *   - which environment the site screen opens on (a staging build opens on Staging, with the test
 *     environments already revealed; production shows only CapHive), and
 *   - the app's identity: staging and production builds are the SAME app (com.caphive.lp, named
 *     "CapHive"), so a tester's phone runs exactly what investors get. Only the development build
 *     — a dev client that loads JavaScript from a laptop — is a separate app beside it.
 * Links into the app use the caphive:// scheme (push notifications); no https universal links.
 */
const DEFAULT_ENVIRONMENT = { development: 'custom', staging: 'staging', production: 'production' };

module.exports = ({ config }) => {
  const env = process.env.APP_ENV ?? 'development';
  const devClient = env === 'development';

  return {
    ...config,
    owner: 'caphive',
    name: devClient ? 'CapHive (development)' : 'CapHive',
    slug: config.slug ?? 'caphive-lp',
    ios: {
      ...config.ios,
      bundleIdentifier: devClient ? 'com.caphive.lp.development' : 'com.caphive.lp',
    },
    android: {
      ...config.android,
      package: devClient ? 'com.caphive.lp.development' : 'com.caphive.lp',
    },
    extra: {
      ...config.extra,
      appEnv: env,
      defaultEnvironment: DEFAULT_ENVIRONMENT[env] ?? 'production',
      eas: { projectId: process.env.EAS_PROJECT_ID ?? config.extra?.eas?.projectId },
    },
  };
};

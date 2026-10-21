import { useEffect } from 'react';
import { Alert, Platform } from 'react-native';
import * as LocalAuthentication from 'expo-local-authentication';

import { useAuth } from '@/auth/session';
import { getItem, setItem } from '@/auth/storage';
import AppTabs from '@/components/app-tabs';
import { FundManagerProvider } from '@/lib/fund-manager';
import { registerForPush, useNotificationTaps } from '@/lib/push';

const ONBOARDED = 'caphive.onboarded';

/**
 * The signed-in app. On the first sign-in on a phone it asks — with a reason — for notification
 * permission and offers Face ID / fingerprint (proposal A5, A6; principle 12). Every later launch
 * re-registers the push address, which may have changed — and does so again on every site the app
 * switches to, so each region can push to this phone (lp-mobile-multi-site design card ②).
 */
export default function TabsLayout() {
  return (
    <FundManagerProvider>
      <SignedInApp />
    </FundManagerProvider>
  );
}

function SignedInApp() {
  const { setBiometric, site } = useAuth();
  useNotificationTaps(true);

  useEffect(() => {
    if (Platform.OS === 'web') return;
    (async () => {
      if (await getItem(ONBOARDED)) {
        registerForPush().catch(() => {});
        return;
      }
      await setItem(ONBOARDED, '1');
      Alert.alert('Stay on top of capital calls', 'Get notified when a capital call or document needs you.', [
        { text: 'Not now', style: 'cancel', onPress: offerBiometric },
        { text: 'Turn on', onPress: async () => { await registerForPush().catch(() => {}); offerBiometric(); } },
      ]);
    })();

    async function offerBiometric() {
      if (!(await LocalAuthentication.hasHardwareAsync()) || !(await LocalAuthentication.isEnrolledAsync())) return;
      Alert.alert('Unlock with Face ID?', 'Open CapHive with Face ID or your fingerprint instead of your password.', [
        { text: 'Not now', style: 'cancel' },
        { text: 'Use Face ID', onPress: () => setBiometric(true) },
      ]);
    }
  }, [setBiometric, site]);

  return <AppTabs />;
}

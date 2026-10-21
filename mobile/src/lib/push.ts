import Constants from 'expo-constants';
import * as Device from 'expo-device';
import * as Notifications from 'expo-notifications';
import { useEffect, useRef } from 'react';
import { Linking, Platform } from 'react-native';

import { updateDevice, useMe } from '@/api/queries';
import { useAuth } from '@/auth/session';
import { fundManagerKey, setItem } from '@/auth/storage';
import { useFundManager } from '@/lib/fund-manager';
import { openLink } from '@/lib/links';

/**
 * Push notifications (design card ⑥). The server decides who is pushed; the app only:
 *   - asks for permission AFTER the first sign-in, with a one-line reason (proposal principle 12)
 *   - sends its Expo push address to PUT /api/mobile/v1/device
 *   - opens the exact item when a notification is tapped (H17)
 */
Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldShowBanner: true, shouldShowList: true, shouldPlaySound: false, shouldSetBadge: true,
  }),
});

export type PushPermission = 'granted' | 'denied' | 'undetermined' | 'unsupported';

export async function pushPermission(): Promise<PushPermission> {
  if (Platform.OS === 'web' || !Device.isDevice) return 'unsupported';
  const { status } = await Notifications.getPermissionsAsync();
  return status as PushPermission;
}

/** Ask (if not asked yet) and register this phone's push address with CapHive */
export async function registerForPush(): Promise<PushPermission> {
  if (Platform.OS === 'web' || !Device.isDevice) return 'unsupported';
  let { status } = await Notifications.getPermissionsAsync();
  if (status === 'undetermined') status = (await Notifications.requestPermissionsAsync()).status;
  if (status !== 'granted') return status as PushPermission;

  if (Platform.OS === 'android') {
    await Notifications.setNotificationChannelAsync('default', { name: 'CapHive', importance: Notifications.AndroidImportance.HIGH });
  }
  const projectId = Constants.expoConfig?.extra?.eas?.projectId as string | undefined;
  const token = (await Notifications.getExpoPushTokenAsync(projectId ? { projectId } : undefined)).data;
  await updateDevice({ push_token: token });
  return 'granted';
}

export function openPhoneSettings() {
  return Linking.openSettings();
}

/**
 * Opens the linked screen when a notification is tapped — also for the one that launched the app.
 * A notification from the other region or another fund manager first moves the app there
 * (lp-mobile-multi-site MS-H5, MF-H5), so the item opens in the right place.
 */
export function useNotificationTaps(enabled: boolean) {
  const { site, switchRegion } = useAuth();
  const { choose } = useFundManager();
  const me = useMe();
  // The handler is registered once; it reads the latest values through this ref
  const latest = useRef({ site, switchRegion, choose, regions: me.data?.regions ?? [] });
  useEffect(() => {
    latest.current = { site, switchRegion, choose, regions: me.data?.regions ?? [] };
  }, [site, switchRegion, choose, me.data]);

  useEffect(() => {
    if (!enabled || Platform.OS === 'web') return;
    const open = async (response: Notifications.NotificationResponse | null) => {
      const data = response?.notification.request.content.data ?? {};
      const { link, region, fund_manager_id: fundManagerId } = data as { link?: unknown; region?: unknown; fund_manager_id?: unknown };
      const ctx = latest.current;
      const target = typeof region === 'string' && ctx.site && region !== ctx.site.code
        ? ctx.regions.find((r) => r.code === region) : undefined;

      if (target) {
        // Store the pick for the target site first: switching reloads the pick from there
        if (typeof fundManagerId === 'number') await setItem(fundManagerKey(target.url), String(fundManagerId));
        try {
          await ctx.switchRegion(target);
        } catch {
          return; // the switch was refused; the user stays where they are
        }
      } else if (typeof fundManagerId === 'number') {
        ctx.choose(fundManagerId);
      }
      if (typeof link === 'string') openLink(link);
    };
    Notifications.getLastNotificationResponseAsync().then(open);
    const sub = Notifications.addNotificationResponseReceivedListener(open);
    return () => sub.remove();
  }, [enabled]);
}

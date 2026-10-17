import Constants from 'expo-constants';
import * as Device from 'expo-device';
import * as Notifications from 'expo-notifications';
import { useEffect } from 'react';
import { Linking, Platform } from 'react-native';

import { updateDevice } from '@/api/queries';
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

/** Opens the linked screen when a notification is tapped — also for the one that launched the app */
export function useNotificationTaps(enabled: boolean) {
  useEffect(() => {
    if (!enabled || Platform.OS === 'web') return;
    const open = (response: Notifications.NotificationResponse | null) => {
      const link = response?.notification.request.content.data?.link;
      if (typeof link === 'string') openLink(link);
    };
    Notifications.getLastNotificationResponseAsync().then(open);
    const sub = Notifications.addNotificationResponseReceivedListener(open);
    return () => sub.remove();
  }, [enabled]);
}

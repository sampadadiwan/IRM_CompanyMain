import { useEffect, useState } from 'react';
import { StyleSheet, View } from 'react-native';

import { updateDevice, useMe, useUpdatePushPreferences } from '@/api/queries';
import type { PushCategory } from '@/api/types';
import { Spacing } from '@/constants/theme';
import { openPhoneSettings, pushPermission, registerForPush, type PushPermission } from '@/lib/push';
import { AppText, Button, Card, Divider, SkeletonCard } from '@/ui/primitives';
import { Screen } from '@/ui/screen';
import { Toggle } from '@/ui/toggle';

const CATEGORIES: { key: PushCategory; label: string; hint?: string }[] = [
  { key: 'capital_calls', label: 'Capital calls & reminders' },
  { key: 'distributions', label: 'Distributions' },
  { key: 'documents', label: 'Documents & signatures' },
  { key: 'other', label: 'Everything else', hint: 'KYC, approvals, deals, fund news' },
];

/**
 * Profile › Notifications (US-7): push on this phone, and four categories that apply to all the
 * user's phones. Email is the fund manager's and is never changed here.
 */
export default function NotificationSettingsScreen() {
  const me = useMe();
  const update = useUpdatePushPreferences();
  const [permission, setPermission] = useState<PushPermission>('undetermined');
  // The switch shows the server's value until the user flips it
  const [phoneOverride, setPhoneOn] = useState<boolean | null>(null);
  const phoneOn = phoneOverride ?? me.data?.device.push_enabled ?? false;

  useEffect(() => { pushPermission().then(setPermission); }, []);

  if (me.isPending || !me.data) return <Screen back title="Notifications"><SkeletonCard lines={4} /></Screen>;
  const prefs = me.data.push_preferences;

  return (
    <Screen back title="Notifications">
      {permission === 'denied' ? (
        // E34 — switched off in the phone's settings
        <Card>
          <AppText variant="bodyStrong">Off in phone settings</AppText>
          <AppText color="textSecondary">Allow notifications for CapHive in your phone&apos;s settings to get alerts.</AppText>
          <Button title="Open phone settings" kind="secondary" onPress={openPhoneSettings} />
        </Card>
      ) : permission === 'undetermined' ? (
        <Card>
          <AppText color="textSecondary">Get notified when a capital call or document needs you.</AppText>
          <Button title="Turn on notifications" onPress={async () => setPermission(await registerForPush())} />
        </Card>
      ) : null}

      <Card>
        <View style={styles.row}>
          <AppText variant="bodyStrong" style={styles.grow}>Push notifications on this phone</AppText>
          <Toggle value={!!phoneOn} accessibilityLabel="Push notifications on this phone"
            onValueChange={async (on) => { setPhoneOn(on); await updateDevice({ push_enabled: on }); me.refetch(); }} />
        </View>
      </Card>

      <Card>
        {CATEGORIES.map((c, i) => (
          <View key={c.key}>
            {i > 0 ? <Divider /> : null}
            <View style={styles.row}>
              <View style={styles.grow}>
                <AppText>{c.label}</AppText>
                {c.hint ? <AppText variant="caption" color="textSecondary">{c.hint}</AppText> : null}
              </View>
              <Toggle value={prefs[c.key]} accessibilityLabel={c.label}
                onValueChange={(on) => update.mutate({ [c.key]: on })} />
            </View>
          </View>
        ))}
      </Card>
      <AppText variant="caption" color="textSecondary">
        These apply to all your phones. Email alerts are managed by your fund manager and are not affected here.
      </AppText>
    </Screen>
  );
}

const styles = StyleSheet.create({
  row: { flexDirection: 'row', alignItems: 'center', gap: Spacing.three, minHeight: 44 },
  grow: { flex: 1 },
});

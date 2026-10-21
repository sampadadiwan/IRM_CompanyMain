import { router } from 'expo-router';
import * as LocalAuthentication from 'expo-local-authentication';
import { Fragment, useEffect, useState } from 'react';
import { Alert, Platform, StyleSheet, View } from 'react-native';

import { APP_VERSION, type Region } from '@/api/config';
import { useMe } from '@/api/queries';
import { useAuth } from '@/auth/session';
import { Spacing } from '@/constants/theme';
import { AppText, Button, Card, Divider, Icon, Pressy, SkeletonCard } from '@/ui/primitives';
import { Screen } from '@/ui/screen';
import { Toggle } from '@/ui/toggle';

/** Profile: notification settings, Face ID, region and sign out — nothing more */
export default function ProfileScreen() {
  const me = useMe();
  const { biometricEnabled, setBiometric, signOut, openSitePicker, site, switchRegion } = useAuth();
  const [canBiometric, setCanBiometric] = useState(false);
  const [switching, setSwitching] = useState<string | null>(null);
  // The regions this user belongs to — the website's region dropdown (lp-mobile-multi-site ②)
  const regions = me.data?.regions ?? [];

  const switchTo = async (region: Region) => {
    setSwitching(region.code);
    try {
      await switchRegion(region);
    } catch (e) {
      Alert.alert("Couldn't switch region", e instanceof Error ? e.message : 'Please try again.');
    } finally {
      setSwitching(null);
    }
  };

  useEffect(() => {
    if (Platform.OS === 'web') return;
    (async () => setCanBiometric((await LocalAuthentication.hasHardwareAsync()) && (await LocalAuthentication.isEnrolledAsync())))();
  }, []);

  return (
    <Screen title="Profile" tabs onRefresh={() => me.refetch()}>
      {me.isPending ? <SkeletonCard lines={2} /> : me.data ? (
        <Card>
          <AppText variant="heading">{me.data.user.first_name} {me.data.user.last_name}</AppText>
          <AppText color="textSecondary">{me.data.user.email}</AppText>
          {me.data.investor_name ? <AppText color="textSecondary">{me.data.investor_name}</AppText> : null}
        </Card>
      ) : null}

      <Card>
        <Pressy onPress={() => router.push('/kyc')} accessibilityRole="button" accessibilityLabel="KYC">
          <View style={styles.row}>
            <Icon name="person.crop.circle" />
            <AppText style={styles.grow}>KYC</AppText>
            <Icon name="chevron.right" />
          </View>
        </Pressy>
        <Divider />
        <Pressy onPress={() => router.push('/profile/notifications')} accessibilityRole="button" accessibilityLabel="Notification settings">
          <View style={styles.row}>
            <Icon name="bell" />
            <AppText style={styles.grow}>Notifications</AppText>
            <Icon name="chevron.right" />
          </View>
        </Pressy>
        {canBiometric ? (
          <>
            <Divider />
            <View style={styles.row}>
              <Icon name="lock.fill" />
              <AppText style={styles.grow}>Unlock with Face ID / fingerprint</AppText>
              <Toggle value={biometricEnabled} onValueChange={setBiometric}
                accessibilityLabel="Unlock with Face ID or fingerprint" />
            </View>
          </>
        ) : null}
        <Divider />
        <View style={styles.row}>
          <Icon name="globe" />
          <AppText style={styles.grow}>Region</AppText>
          <AppText color="textSecondary">{site?.label}{site && site.env !== 'production' ? ` · ${site.env}` : ''}</AppText>
        </View>
      </Card>

      {/* MS-H3 — switch region without signing in again, as the website's region dropdown does.
          Shown only to a user who belongs to two or more regions (MS-E2). */}
      {regions.length > 1 ? (
        <Card>
          <AppText variant="heading" accessibilityRole="header">Switch region</AppText>
          {regions.map((r, i) => (
            <Fragment key={r.code}>
              {i > 0 ? <Divider /> : null}
              <Pressy onPress={() => r.code !== site?.code && !switching && switchTo(r)} accessibilityRole="button"
                accessibilityState={{ selected: r.code === site?.code, busy: switching === r.code }} accessibilityLabel={`Switch to ${r.label}`}>
                <View style={styles.row}>
                  <AppText style={styles.grow} variant={r.code === site?.code ? 'bodyStrong' : 'body'}>{r.label}</AppText>
                  {r.code === site?.code ? <Icon name="checkmark" color="accent" />
                    : switching === r.code ? <AppText color="textSecondary">Switching…</AppText> : <Icon name="chevron.right" />}
                </View>
              </Pressy>
            </Fragment>
          ))}
        </Card>
      ) : null}

      <AppText variant="caption" color="textSecondary">
        Lost a phone? Sign it out from the CapHive website under Profile › Mobile Devices.
      </AppText>

      <Button title="Sign out" kind="danger" onPress={signOut} />
      <Button title="Change site" kind="secondary" onPress={openSitePicker} />
      <AppText variant="caption" color="textSecondary" style={styles.center}>CapHive {APP_VERSION}</AppText>
    </Screen>
  );
}

const styles = StyleSheet.create({
  row: { flexDirection: 'row', alignItems: 'center', gap: Spacing.three, minHeight: 44 },
  grow: { flex: 1 },
  center: { textAlign: 'center' },
});

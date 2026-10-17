import { router } from 'expo-router';
import * as LocalAuthentication from 'expo-local-authentication';
import { useEffect, useState } from 'react';
import { Platform, StyleSheet, View } from 'react-native';

import { currentRegion } from '@/api/client';
import { APP_VERSION } from '@/api/config';
import { useMe } from '@/api/queries';
import { useAuth } from '@/auth/session';
import { Spacing } from '@/constants/theme';
import { AppText, Button, Card, Divider, Icon, Pressy, SkeletonCard } from '@/ui/primitives';
import { Screen } from '@/ui/screen';
import { Toggle } from '@/ui/toggle';

/** Profile: notification settings, Face ID, region and sign out — nothing more */
export default function ProfileScreen() {
  const me = useMe();
  const { biometricEnabled, setBiometric, signOut, changeRegion } = useAuth();
  const [canBiometric, setCanBiometric] = useState(false);

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
          <AppText color="textSecondary">{currentRegion()?.label}</AppText>
        </View>
      </Card>

      <AppText variant="caption" color="textSecondary">
        Lost a phone? Sign it out from the CapHive website under Profile › Mobile Devices.
      </AppText>

      <Button title="Sign out" kind="danger" onPress={signOut} />
      <Button title="Change region" kind="secondary" onPress={changeRegion} />
      <AppText variant="caption" color="textSecondary" style={styles.center}>CapHive {APP_VERSION}</AppText>
    </Screen>
  );
}

const styles = StyleSheet.create({
  row: { flexDirection: 'row', alignItems: 'center', gap: Spacing.three, minHeight: 44 },
  grow: { flex: 1 },
  center: { textAlign: 'center' },
});

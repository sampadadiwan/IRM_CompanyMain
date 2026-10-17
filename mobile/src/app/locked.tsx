import { useEffect } from 'react';
import { StyleSheet, View } from 'react-native';

import { useAuth } from '@/auth/session';
import { Spacing } from '@/constants/theme';
import { AppText, Button, Icon } from '@/ui/primitives';
import { Screen } from '@/ui/screen';

/** Face ID / fingerprint unlock (US-2, E31, E32) — asks straight away, with a button to retry */
export default function LockedScreen() {
  const { unlock, signOut } = useAuth();
  useEffect(() => { unlock(); }, [unlock]);
  return (
    <Screen>
      <View style={styles.center}>
        <Icon name="lock.fill" size={40} color="accent" />
        <AppText variant="title">CapHive is locked</AppText>
        <AppText color="textSecondary">Unlock with Face ID or your fingerprint.</AppText>
      </View>
      <Button title="Unlock" onPress={unlock} />
      <Button title="Sign in with password instead" kind="secondary" onPress={signOut} />
    </Screen>
  );
}

const styles = StyleSheet.create({ center: { alignItems: 'center', gap: Spacing.three, marginVertical: Spacing.six } });

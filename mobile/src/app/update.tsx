import { Linking, Platform, StyleSheet, View } from 'react-native';

import { Spacing } from '@/constants/theme';
import { AppText, Button, Icon } from '@/ui/primitives';
import { Screen } from '@/ui/screen';

const STORE = Platform.select({
  ios: 'https://apps.apple.com/app/caphive',
  android: 'https://play.google.com/store/apps/details?id=com.caphive.lp',
  default: 'https://caphive.com',
});

/** The server needs a newer app (spec "Forced update", X21) — nothing else is usable */
export default function UpdateScreen() {
  return (
    <Screen>
      <View style={styles.center}>
        <Icon name="arrow.up.right" size={40} color="accent" />
        <AppText variant="title">Update required</AppText>
        <AppText color="textSecondary" style={styles.text}>Please update CapHive to continue.</AppText>
      </View>
      <Button title="Update" onPress={() => Linking.openURL(STORE)} />
    </Screen>
  );
}

const styles = StyleSheet.create({
  center: { alignItems: 'center', gap: Spacing.three, marginVertical: Spacing.six },
  text: { textAlign: 'center' },
});

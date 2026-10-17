import { StyleSheet, View } from 'react-native';

import { REGIONS } from '@/api/config';
import { useAuth } from '@/auth/session';
import { Spacing } from '@/constants/theme';
import { AppText, Card, Icon } from '@/ui/primitives';
import { Screen } from '@/ui/screen';

/** A2 — India and US are separate CapHive sites; the account lives in one of them */
export default function RegionScreen() {
  const { chooseRegion } = useAuth();
  return (
    <Screen>
      <View style={styles.brand}>
        <AppText variant="title">CapHive</AppText>
        <AppText color="textSecondary">Your investments, capital calls and documents — on your phone.</AppText>
      </View>
      <AppText variant="heading" accessibilityRole="header">Where is your account?</AppText>
      {REGIONS.map((region) => (
        <Card key={region.code} onPress={() => chooseRegion(region.code)} accessibilityLabel={`Choose ${region.label}`}>
          <View style={styles.row}>
            <AppText variant="bodyStrong">{region.label}</AppText>
            <Icon name="chevron.right" />
          </View>
        </Card>
      ))}
      <AppText variant="caption" color="textSecondary">
        Pick the site you sign in to on the web. You can change this later.
      </AppText>
    </Screen>
  );
}

const styles = StyleSheet.create({
  brand: { gap: Spacing.two, marginTop: Spacing.five, marginBottom: Spacing.four },
  row: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', minHeight: 32 },
});

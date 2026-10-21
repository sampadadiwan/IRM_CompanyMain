import { router, useLocalSearchParams } from 'expo-router';
import { StyleSheet, View } from 'react-native';

import { useCommitment, useDistributions } from '@/api/queries';
import { Spacing } from '@/constants/theme';
import { formatDate } from '@/format/date';
import { formatMoney } from '@/format/money';
import { ListCard } from '@/ui/list-card';
import { AppText, Icon, Pressy } from '@/ui/primitives';
import { Screen } from '@/ui/screen';

/** Payouts from the fund to this folio — the website fund page's Distributions section */
export default function FundDistributionsScreen() {
  const { id, name } = useLocalSearchParams<{ id: string; name?: string }>();
  const commitment = useCommitment(Number(id));
  const distributions = useDistributions(Number(id));
  const currency = commitment.data?.fund_currency ?? 'INR';
  return (
    <Screen back title="Distributions" subtitle={name} onRefresh={() => distributions.refetch()} updatedAt={distributions.dataUpdatedAt}>
      <ListCard query={distributions} empty="No distributions yet" render={(p) => (
        <Pressy onPress={() => router.push({ pathname: '/distributions/[id]', params: { id: String(p.id) } })}
          accessibilityRole="button" accessibilityLabel={p.capital_distribution_title}>
          <View style={styles.item}>
            <View style={styles.grow}>
              <AppText variant="bodyStrong">{p.capital_distribution_title}</AppText>
              <AppText variant="caption" color="textSecondary">{p.payment_date ? `paid ${formatDate(p.payment_date)}` : 'scheduled'}</AppText>
            </View>
            <AppText variant="bodyStrong" style={styles.tabular}>{formatMoney(p.net_payable, currency)}</AppText>
            <Icon name="chevron.right" />
          </View>
        </Pressy>
      )} />
    </Screen>
  );
}

const styles = StyleSheet.create({
  grow: { flex: 1 },
  item: { flexDirection: 'row', alignItems: 'center', gap: Spacing.two, paddingVertical: Spacing.one },
  tabular: { fontVariant: ['tabular-nums'] },
});

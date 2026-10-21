import { router, useLocalSearchParams } from 'expo-router';
import { StyleSheet, View } from 'react-native';

import { useCalls } from '@/api/queries';
import { Spacing } from '@/constants/theme';
import { formatDate } from '@/format/date';
import { formatMoney } from '@/format/money';
import { ListCard } from '@/ui/list-card';
import { AppText, Icon, Pressy, StatusPill } from '@/ui/primitives';
import { Screen } from '@/ui/screen';

/** The folio's capital calls, newest first — the website fund page's Calls section */
export default function FundCallsScreen() {
  const { id, name } = useLocalSearchParams<{ id: string; name?: string }>();
  const calls = useCalls(Number(id));
  return (
    <Screen back title="Capital calls" subtitle={name} onRefresh={() => calls.refetch()} updatedAt={calls.dataUpdatedAt}>
      <ListCard query={calls} empty="No capital calls yet" render={(rem) => (
        <Pressy onPress={() => router.push({ pathname: '/capital-calls/[id]', params: { id: String(rem.id) } })}
          accessibilityRole="button" accessibilityLabel={`${rem.capital_call_name}, ${rem.status}`}>
          <View style={styles.item}>
            <View style={styles.grow}>
              <AppText variant="bodyStrong">{rem.capital_call_name}</AppText>
              <AppText variant="caption" color="textSecondary">
                {rem.status === 'Paid' && rem.payment_date ? `paid ${formatDate(rem.payment_date)}` : `due ${formatDate(rem.due_date)}`}
              </AppText>
            </View>
            <View style={styles.end}>
              <AppText variant="bodyStrong" style={styles.tabular}>{formatMoney(rem.call_amount + (rem.other_fee ?? 0), rem.fund_currency)}</AppText>
              <StatusPill status={rem.status} />
            </View>
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
  end: { alignItems: 'flex-end', gap: 4 },
  tabular: { fontVariant: ['tabular-nums'] },
});

import { useLocalSearchParams } from 'expo-router';
import { StyleSheet, View } from 'react-native';

import { useCommitment, usePortfolio } from '@/api/queries';
import { Spacing } from '@/constants/theme';
import { formatMoney } from '@/format/money';
import { openWebsitePage } from '@/lib/links';
import { ListCard } from '@/ui/list-card';
import { AppText, Icon, Pressy } from '@/ui/primitives';
import { Screen } from '@/ui/screen';

/**
 * The fund's holdings the LP may see — the website fund page's Portfolio section. Whole fund, or only
 * the holdings allocated to this LP's folio: the server's scope decides (LpPortfolioVisibility).
 */
export default function FundPortfolioScreen() {
  const { id, name } = useLocalSearchParams<{ id: string; name?: string }>();
  const commitment = useCommitment(Number(id));
  const portfolio = usePortfolio(commitment.data?.fund_id);
  return (
    <Screen back title="Portfolio" subtitle={name} onRefresh={() => portfolio.refetch()} updatedAt={portfolio.dataUpdatedAt}>
      <ListCard query={portfolio} empty="No holdings to show yet" render={(h) => {
        const row = (
          <View style={styles.item}>
            <View style={styles.grow}>
              <AppText variant="bodyStrong">{h.portfolio_company_name}</AppText>
              <AppText variant="caption" color="textSecondary">
                {[h.investment_instrument_name, `cost ${formatMoney(h.cost_of_remaining, h.fund_currency)}`].filter(Boolean).join(' · ')}
              </AppText>
            </View>
            <View style={styles.end}>
              <AppText variant="bodyStrong" style={styles.tabular}>{formatMoney(h.fmv, h.fund_currency)}</AppText>
              <AppText variant="caption" color={h.unrealized_gain < 0 ? 'danger' : 'textSecondary'} style={styles.tabular}>
                {`${h.unrealized_gain >= 0 ? '+' : ''}${formatMoney(h.unrealized_gain, h.fund_currency)}`}
              </AppText>
            </View>
            {h.lp_company_path ? <Icon name="chevron.right" /> : null}
          </View>
        );
        // The LP company page opens on the website, only where the LP may open it
        return h.lp_company_path ? (
          <Pressy onPress={() => openWebsitePage(h.lp_company_path!)} accessibilityRole="button" accessibilityLabel={h.portfolio_company_name}>{row}</Pressy>
        ) : row;
      }} />
    </Screen>
  );
}

const styles = StyleSheet.create({
  grow: { flex: 1 },
  item: { flexDirection: 'row', alignItems: 'center', gap: Spacing.two, paddingVertical: Spacing.one },
  end: { alignItems: 'flex-end', gap: 4 },
  tabular: { fontVariant: ['tabular-nums'] },
});

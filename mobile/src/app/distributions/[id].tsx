import { router, useLocalSearchParams } from 'expo-router';
import { StyleSheet, View } from 'react-native';

import { useDistribution } from '@/api/queries';
import { Spacing } from '@/constants/theme';
import { formatDate } from '@/format/date';
import { formatMoney } from '@/format/money';
import { AppText, Button, Card, ErrorState, HeroAmount, Icon, Row, SkeletonCard, StatusPill } from '@/ui/primitives';
import { Screen } from '@/ui/screen';

/**
 * The Distribution screen: what the investor is paid and when, with one primary action — the
 * distribution notice, which carries the full breakdown. The Capital call screen's twin; reads the
 * website's own GET /capital_distribution_payments/:id.json.
 */
export default function DistributionScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const payment = useDistribution(Number(id));

  if (payment.isPending) return <Screen back><SkeletonCard lines={5} /></Screen>;
  if (payment.isError) {
    return <Screen back><ErrorState message={payment.error.message} onRetry={() => payment.refetch()} /></Screen>;
  }

  const p = payment.data;
  // Amounts are in the fund's currency (the jbuilder's fund-currency block)
  const currency = p.fund_currency;
  // Gross is before tax and other deductions; net is what is actually paid out
  const deductions = p.gross_payable - p.net_payable;
  const status = p.completed ? 'Paid' : 'Scheduled';
  return (
    <Screen back title={p.capital_distribution_title} subtitle={p.fund_name} onRefresh={() => payment.refetch()} updatedAt={payment.dataUpdatedAt}>
      {/* The hero answers "how much, and when" */}
      <Card>
        <View style={styles.statusRow}>
          <AppText color="textSecondary">Net payable</AppText>
          <StatusPill status={status} />
        </View>
        <HeroAmount>{formatMoney(p.net_payable, currency)}</HeroAmount>
        {p.payment_date ? (
          <AppText color="textSecondary">{p.completed ? `Paid on ${formatDate(p.payment_date)}` : `Scheduled for ${formatDate(p.payment_date)}`}</AppText>
        ) : null}
      </Card>
      <Card>
        <Row label="Gross payable" value={formatMoney(p.gross_payable, currency)} />
        <Row label="Tax & deductions" value={formatMoney(deductions, currency)} />
        <Row label="Net payable" value={formatMoney(p.net_payable, currency)} strong />
      </Card>

      {p.notice_document_id ? (
        <>
          <View style={styles.note}>
            <Icon name="doc.text" />
            <AppText color="textSecondary" style={styles.grow}>The distribution notice has the full breakdown.</AppText>
          </View>
          <Button title="View distribution notice" icon="doc.text"
            onPress={() => router.push({ pathname: '/documents/[id]', params: { id: String(p.notice_document_id) } })} />
        </>
      ) : (
        // Not generated / approved yet
        <Card>
          <AppText color="textSecondary">The distribution notice isn&apos;t available yet.</AppText>
        </Card>
      )}
    </Screen>
  );
}

const styles = StyleSheet.create({
  statusRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  note: { flexDirection: 'row', gap: Spacing.two, alignItems: 'center' },
  grow: { flex: 1 },
});

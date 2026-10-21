import { router, useLocalSearchParams } from 'expo-router';
import { Fragment } from 'react';
import { Linking, StyleSheet, View } from 'react-native';

import { useRemittance, useRemittancePayments } from '@/api/queries';
import { Spacing } from '@/constants/theme';
import { formatDate } from '@/format/date';
import { formatMoney } from '@/format/money';
import { AppText, Button, Card, Divider, ErrorState, Icon, Pressy, Row, SkeletonCard, StatusPill, HeroAmount } from '@/ui/primitives';
import { Screen } from '@/ui/screen';

/**
 * The Capital call screen (US-4, H6): what to pay and by when, with one primary action — the call
 * notice, which carries the payment instructions and the fund's bank details. Reads the website's
 * own GET /capital_remittances/:id.json.
 */
export default function CapitalCallScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const remittance = useRemittance(Number(id));
  const payments = useRemittancePayments(Number(id));

  if (remittance.isPending) return <Screen back><SkeletonCard lines={5} /></Screen>;
  if (remittance.isError) {
    return <Screen back><ErrorState message={remittance.error.message} onRetry={() => remittance.refetch()} /></Screen>;
  }

  const r = remittance.data;
  const callAmount = r.call_amount + (r.other_fee ?? 0);
  return (
    <Screen back title={r.capital_call_name} subtitle={r.fund_name} onRefresh={() => Promise.all([remittance.refetch(), payments.refetch()])} updatedAt={remittance.dataUpdatedAt}>
      {/* The hero answers "how much, by when" */}
      <Card>
        <View style={styles.statusRow}>
          <AppText color="textSecondary">{r.due_amount > 0 ? 'Amount due' : 'Call amount'}</AppText>
          <StatusPill status={r.status} />
        </View>
        <HeroAmount>{formatMoney(r.due_amount > 0 ? r.due_amount : callAmount, r.fund_currency)}</HeroAmount>
        <AppText color="textSecondary">{r.status === 'Paid' && r.payment_date ? `Paid on ${formatDate(r.payment_date)}` : `Due by ${formatDate(r.due_date)}`}</AppText>
      </Card>
      <Card>
        <Row label="Call amount" value={formatMoney(callAmount, r.fund_currency)} strong />
        <Row label="Received" value={formatMoney(r.collected_amount, r.fund_currency)} />
        <Row label="Due" value={formatMoney(r.due_amount, r.fund_currency)} />
        <Row label="Due by" value={formatDate(r.due_date)} />
      </Card>

      {/* What the fund has recorded against this call, with the proof the GP attached */}
      {payments.data && payments.data.length > 0 ? (
        <Card>
          <AppText variant="bodyStrong">Payments received</AppText>
          {payments.data.map((p, i) => (
            <Fragment key={p.id}>
              {i > 0 ? <Divider /> : null}
              <View style={styles.payment}>
                <View style={styles.grow}>
                  <AppText style={styles.tabular}>{formatMoney(p.amount, p.currency)}</AppText>
                  <AppText variant="caption" color="textSecondary">
                    {[p.payment_date ? formatDate(p.payment_date) : null, p.reference_no ? `Ref ${p.reference_no}` : null].filter(Boolean).join(' · ')}
                  </AppText>
                </View>
                {p.payment_proof_url ? (
                  <Pressy onPress={() => Linking.openURL(p.payment_proof_url!)} accessibilityRole="button" accessibilityLabel="View payment proof">
                    <View style={styles.proof}>
                      <AppText color="accent">View proof</AppText>
                      <Icon name="open" color="accent" />
                    </View>
                  </Pressy>
                ) : null}
              </View>
            </Fragment>
          ))}
        </Card>
      ) : null}

      {r.notice_document_id ? (
        <>
          <View style={styles.note}>
            <Icon name="doc.text" />
            <AppText color="textSecondary" style={styles.grow}>Payment instructions and the fund&apos;s bank details are in the call notice.</AppText>
          </View>
          <Button title="View call notice" icon="doc.text"
            onPress={() => router.push({ pathname: '/documents/[id]', params: { id: String(r.notice_document_id) } })} />
        </>
      ) : (
        // E22 — not generated / approved yet
        <Card>
          <AppText color="textSecondary">The call notice isn&apos;t available yet.</AppText>
        </Card>
      )}
    </Screen>
  );
}

const styles = StyleSheet.create({
  statusRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  note: { flexDirection: 'row', gap: Spacing.two, alignItems: 'center' },
  grow: { flex: 1 },
  payment: { flexDirection: 'row', alignItems: 'center', gap: Spacing.two, paddingVertical: Spacing.one },
  proof: { flexDirection: 'row', alignItems: 'center', gap: 4 },
  tabular: { fontVariant: ['tabular-nums'] },
});

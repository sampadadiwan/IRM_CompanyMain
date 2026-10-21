import { router, useLocalSearchParams } from 'expo-router';
import { Fragment, useState } from 'react';
import { StyleSheet, View } from 'react-native';

import { useCalls, useCommitment, useDistributions, useDocuments, useHome } from '@/api/queries';
import { Spacing } from '@/constants/theme';
import { formatDate } from '@/format/date';
import { formatMoney, moneyParts } from '@/format/money';
import { openWebsitePage } from '@/lib/links';
import {
  AppText, Button, Card, Divider, HeroAmount, EmptyState, ErrorState, Icon, ProgressBar, Pressy, Row, Segmented, SkeletonCard, StatTile, StatusPill,
} from '@/ui/primitives';
import { Screen } from '@/ui/screen';

type Segment = 'calls' | 'distributions' | 'documents';

const pct = (part: number, whole: number) => (whole > 0 ? (part / whole) * 100 : 0);

/**
 * The Fund screen (US-3, proposal "Fund"): exact totals, then Calls / Distributions / Documents.
 * Calls, distributions and totals come from the website's own JSON endpoints; documents from the
 * app's LP document list. Evergreen funds show their holding, and Subscribe / Redeem open the
 * website's wizards in the in-app browser.
 */
export default function FundScreen() {
  const params = useLocalSearchParams<{ id: string; segment?: Segment; name?: string; kind?: string }>();
  const id = Number(params.id);
  const [segment, setSegment] = useState<Segment>(params.segment ?? 'calls');
  const commitment = useCommitment(id);
  const home = useHome();
  const card = home.data?.cards.find((c) => c.commitment_id === id);
  const evergreen = (params.kind ?? card?.kind) === 'evergreen';

  const calls = useCalls(id, segment === 'calls');
  const distributions = useDistributions(id, segment === 'distributions');
  const docs = useDocuments({ commitmentId: id });
  const currency = commitment.data?.fund_currency ?? card?.currency ?? 'INR';

  return (
    <>
      <Screen back title={params.name ?? commitment.data?.fund_name ?? ''} subtitle={card ? `${card.entity_name} · Folio ${card.folio_id}` : undefined}
        onRefresh={() => Promise.all([commitment.refetch(), calls.refetch(), distributions.refetch(), docs.refetch()])}
        updatedAt={commitment.dataUpdatedAt}>
        {commitment.isPending ? <SkeletonCard lines={4} /> : commitment.isError ? (
          <ErrorState message={commitment.error.message} onRetry={() => commitment.refetch()} />
        ) : evergreen && card?.kind === 'evergreen' ? (
          <Card>
            <Row label="Value" value={card.value ? formatMoney(card.value) : 'NAV not yet published'} strong />
            <Row label="Units" value={Number(card.units).toLocaleString('en-IN', { maximumFractionDigits: 4 })} />
            <Row label="NAV per unit" value={card.nav_per_unit ? `${formatMoney(card.nav_per_unit)} · ${formatDate(card.nav_date)}` : '—'} />
            <Row label="Gain" value={card.gain ? formatMoney(card.gain) : '—'} />
            <View style={styles.actions}>
              <View style={styles.grow}><Button title="Subscribe" kind="secondary" onPress={() => openWebsitePage(`/capital_commitments/${id}`)} /></View>
              <View style={styles.grow}><Button title="Redeem" kind="secondary" onPress={() => openWebsitePage(`/capital_commitments/${id}`)} /></View>
            </View>
          </Card>
        ) : (
          <>
            {/* Exact figures, website card's own (Committed, Called, Received, Due, Distributed) */}
            <Card>
              <AppText color="textSecondary">Committed</AppText>
              <HeroAmount>{formatMoney(commitment.data.committed_amount, currency)}</HeroAmount>
              <ProgressBar value={pct(commitment.data.call_amount, commitment.data.committed_amount)}
                label={`${Math.round(pct(commitment.data.call_amount, commitment.data.committed_amount))}% called`} />
              <AppText variant="caption" color="textSecondary">
                {Math.round(pct(commitment.data.call_amount, commitment.data.committed_amount))}% called
              </AppText>
            </Card>
            <View style={styles.tiles}>
              <StatTile {...moneyParts(commitment.data.call_amount, currency)} label="Called" icon="trending" />
              <StatTile {...moneyParts(commitment.data.collected_amount, currency)} label="Received" icon="checkmark" />
            </View>
            <View style={styles.tiles}>
              <StatTile {...moneyParts(commitment.data.due_amount, currency)} label="Due" icon="clock" accent={commitment.data.due_amount > 0} />
              <StatTile {...moneyParts(commitment.data.distribution_amount, currency)} label="Distributed" icon="cash" />
            </View>
          </>
        )}

        <Segmented<Segment> value={segment} onChange={setSegment} options={[
          { value: 'calls', label: 'Calls' },
          { value: 'distributions', label: 'Distributions' },
          { value: 'documents', label: 'Documents' },
        ]} />

        {segment === 'calls' ? (
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
        ) : segment === 'distributions' ? (
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
        ) : (
          <ListCard query={{ ...docs, data: docs.data?.pages.flatMap((pg) => pg.items) }} empty="No documents yet for this fund" render={(d) => (
            <Pressy onPress={() => router.push({ pathname: '/documents/[id]', params: { id: String(d.id) } })} accessibilityRole="button" accessibilityLabel={d.name}>
              <View style={styles.item}>
                <Icon name="doc.text" />
                <View style={styles.grow}>
                  <AppText variant="bodyStrong">{d.name}</AppText>
                  <AppText variant="caption" color="textSecondary">{formatDate(d.created_at)}</AppText>
                </View>
                <Icon name="chevron.right" />
              </View>
            </Pressy>
          )} />
        )}
      </Screen>
    </>
  );
}

type ListQuery<T> = { data?: T[]; isPending: boolean; isError: boolean; error: Error | null; refetch: () => unknown };

function ListCard<T extends { id: number }>({ query, render, empty }: { query: ListQuery<T>; render: (row: T) => React.ReactNode; empty: string }) {
  if (query.isPending) return <SkeletonCard lines={3} />;
  if (query.isError) return <ErrorState message={query.error?.message ?? 'Something went wrong.'} onRetry={() => query.refetch()} />;
  if (!query.data?.length) return <EmptyState icon="doc.text" title={empty} />;
  return (
    <Card>
      {query.data.map((row, i) => (
        <Fragment key={row.id}>
          {i > 0 ? <Divider /> : null}
          {render(row)}
        </Fragment>
      ))}
    </Card>
  );
}

const styles = StyleSheet.create({
  grow: { flex: 1 },
  item: { flexDirection: 'row', alignItems: 'center', gap: Spacing.two, paddingVertical: Spacing.one },
  end: { alignItems: 'flex-end', gap: 4 },
  tabular: { fontVariant: ['tabular-nums'] },
  actions: { flexDirection: 'row', gap: Spacing.two, marginTop: Spacing.two },
  tiles: { flexDirection: 'row', gap: Spacing.three },
});

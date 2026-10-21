import { router, useLocalSearchParams } from 'expo-router';
import type { ReactNode } from 'react';
import { StyleSheet, View } from 'react-native';

import { useCalls, useCommitment, useDistributions, useDocuments, useHome, usePortfolio, useRatios, useUnits } from '@/api/queries';
import type { Commitment, DistributionPayment, FundUnit, Remittance } from '@/api/types';
import { Spacing } from '@/constants/theme';
import { formatDate } from '@/format/date';
import { formatMoney, moneyParts } from '@/format/money';
import { openWebsitePage } from '@/lib/links';
import {
  AppText, Button, Card, Divider, HeroAmount, ErrorState, Icon, type IconName, ProgressBar, Pressy, Row, SkeletonCard, StatTile,
} from '@/ui/primitives';
import { Screen } from '@/ui/screen';

const pct = (part: number, whole: number) => (whole > 0 ? (part / whole) * 100 : 0);

/**
 * The Fund screen (US-3, proposal "Fund"): exact totals, the Performance card, then one row per
 * section of the website's LP fund page — Capital calls, Distributions, Portfolio, Units, Documents —
 * each with a one-line summary and opening its own screen. A list, not tabs: it holds any number of
 * sections at any font size. Portfolio and Units (and Performance) appear only when the GP has
 * switched them on for the fund (commitment.lp_sections). Evergreen funds show their holding, and
 * Subscribe / Redeem open the website's wizards in the in-app browser.
 */
export default function FundScreen() {
  const params = useLocalSearchParams<{ id: string; name?: string; kind?: string }>();
  const id = Number(params.id);
  const commitment = useCommitment(id);
  // This commitment's card is on its own fund manager's Home (lp-mobile-multi-site design card ③)
  const fundManagerId = commitment.data?.entity_id ?? null;
  const home = useHome(fundManagerId, fundManagerId != null);
  const card = home.data?.cards.find((c) => c.commitment_id === id);
  const evergreen = (params.kind ?? card?.kind) === 'evergreen';

  // Each row's one-line summary reads the same lists its screen shows (cached for when it opens)
  const sections = commitment.data?.lp_sections;
  const calls = useCalls(id);
  const distributions = useDistributions(id);
  const docs = useDocuments({ commitmentId: id });
  const portfolio = usePortfolio(commitment.data?.fund_id, !!sections?.portfolio);
  const units = useUnits(id, !!sections?.units);
  const currency = commitment.data?.fund_currency ?? card?.currency ?? 'INR';
  const fundName = params.name ?? commitment.data?.fund_name ?? '';
  const open = (screen: 'calls' | 'distributions' | 'portfolio' | 'documents') =>
    router.push({ pathname: `/funds/[id]/${screen}`, params: { id: String(id), name: fundName } });

  return (
    <>
      <Screen back title={fundName} subtitle={card ? `${card.entity_name} · Folio ${card.folio_id}` : undefined}
        onRefresh={() => Promise.all([commitment.refetch(), calls.refetch(), distributions.refetch(), docs.refetch(), portfolio.refetch(), units.refetch()])}
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

        {/* The website's Ratios section, as the headline figures — only when the GP shows ratios */}
        {sections?.ratios && commitment.data ? <PerformanceCard commitment={commitment.data} /> : null}

        {/* One row per section of the website's LP fund page, each opening its own screen */}
        <Card>
          <SectionRow icon="wallet" title="Capital calls" summary={callsSummary(calls.data, commitment.data?.due_amount ?? 0, currency)} onPress={() => open('calls')} />
          <Divider />
          <SectionRow icon="cash" title="Distributions" summary={distributionsSummary(distributions.data)} onPress={() => open('distributions')} />
          {sections?.portfolio ? (
            <>
              <Divider />
              <SectionRow icon="business" title="Portfolio" summary={countSummary(portfolio.data, 'company', 'companies')} onPress={() => open('portfolio')} />
            </>
          ) : null}
          {sections?.units ? (
            <>
              <Divider />
              <SectionRow icon="trending" title="Units" summary={unitsSummary(units.data)}
                onPress={() => router.push({ pathname: '/units/[commitmentId]', params: { commitmentId: String(id), name: fundName } })} />
            </>
          ) : null}
          <Divider />
          <SectionRow icon="doc.text" title="Documents"
            summary={docs.data ? countSummary(docs.data.pages.flatMap((pg) => pg.items), 'document', 'documents', docs.hasNextPage) : undefined}
            onPress={() => open('documents')} />
        </Card>
      </Screen>
    </>
  );
}

/**
 * The headline ratios the website shows above its Ratios list (TVPI, DPI, XIRR…), latest value of
 * each with its date; taps through to every fund-level ratio. Hidden when the fund has none yet.
 */
function PerformanceCard({ commitment }: { commitment: Commitment }) {
  const headline = useRatios(commitment.ratios_fund_id, true);
  const rows = headline.data ?? [];
  if (rows.length === 0) return null;
  const asOf = rows.map((r) => r.end_date ?? '').sort().at(-1);
  return (
    <Card onPress={() => router.push({ pathname: '/ratios/[fundId]', params: { fundId: String(commitment.ratios_fund_id), name: commitment.fund_name, master: commitment.ratios_from_master ? '1' : '', commitmentId: String(commitment.id) } })}
      accessibilityLabel="Performance, see all ratios">
      <View style={styles.headerRow}>
        <AppText variant="bodyStrong">Performance</AppText>
        <AppText variant="caption" color="textSecondary">{asOf ? `as of ${formatDate(asOf)}` : ''}</AppText>
        <Icon name="chevron.right" />
      </View>
      <View style={styles.ratioRow}>
        {rows.slice(0, 3).map((r) => (
          <View key={r.id} style={styles.grow}>
            <AppText variant="caption" color="textSecondary">{r.name}</AppText>
            <AppText variant="bodyStrong" style={styles.tabular}>{r.display_value ?? '—'}</AppText>
          </View>
        ))}
      </View>
      {commitment.ratios_from_master ? (
        <AppText variant="caption" color="textSecondary">Reported for the master fund</AppText>
      ) : null}
    </Card>
  );
}

/** A section of the fund: its title, a one-line summary (blank while loading) and a chevron */
function SectionRow({ icon, title, summary, onPress }: { icon: IconName; title: string; summary?: ReactNode; onPress: () => void }) {
  return (
    <Pressy onPress={onPress} accessibilityRole="button" accessibilityLabel={typeof summary === 'string' ? `${title}, ${summary}` : title}>
      <View style={styles.item}>
        <Icon name={icon} />
        <AppText variant="bodyStrong" style={styles.grow}>{title}</AppText>
        <AppText variant="caption" color="textSecondary" numberOfLines={1} style={styles.summary}>{summary ?? ''}</AppText>
        <Icon name="chevron.right" />
      </View>
    </Pressy>
  );
}

// "2 pending · ₹6,00,000 due", or "3 calls" once everything is paid
function callsSummary(rows: Remittance[] | undefined, due: number, currency: string): string | undefined {
  if (!rows) return undefined;
  const open = rows.filter((r) => r.status === 'Pending' || r.status === 'Overdue').length;
  if (open > 0 && due > 0) return `${open} pending · ${formatMoney(due, currency)} due`;
  return countSummary(rows, 'call', 'calls');
}

// "4 · last paid 12/01/2022"
function distributionsSummary(rows: DistributionPayment[] | undefined): string | undefined {
  if (!rows) return undefined;
  if (rows.length === 0) return 'None yet';
  const lastPaid = rows.map((r) => r.payment_date ?? '').sort().at(-1);
  return lastPaid ? `${rows.length} · last paid ${formatDate(lastPaid)}` : String(rows.length);
}

// "12,345.678 Class A"
function unitsSummary(rows: FundUnit[] | undefined): string | undefined {
  if (!rows) return undefined;
  if (rows.length === 0) return 'None yet';
  const byClass = new Map<string, number>();
  rows.forEach((u) => byClass.set(u.unit_type ?? 'Units', (byClass.get(u.unit_type ?? 'Units') ?? 0) + Number(u.quantity)));
  return [...byClass].map(([cls, qty]) => `${qty.toLocaleString('en-IN', { maximumFractionDigits: 4 })} ${cls}`).join(' · ');
}

// "12 companies", "1 document", "25+ documents" when more pages remain
function countSummary(rows: unknown[] | undefined, one: string, many: string, more = false): string | undefined {
  if (!rows) return undefined;
  if (rows.length === 0) return 'None yet';
  return `${rows.length}${more ? '+' : ''} ${rows.length === 1 && !more ? one : many}`;
}

const styles = StyleSheet.create({
  grow: { flex: 1 },
  item: { flexDirection: 'row', alignItems: 'center', gap: Spacing.two, paddingVertical: Spacing.one },
  tabular: { fontVariant: ['tabular-nums'] },
  actions: { flexDirection: 'row', gap: Spacing.two, marginTop: Spacing.two },
  tiles: { flexDirection: 'row', gap: Spacing.three },
  summary: { flexShrink: 1, maxWidth: '55%', textAlign: 'right' },
  headerRow: { flexDirection: 'row', alignItems: 'center', gap: Spacing.two, justifyContent: 'space-between' },
  ratioRow: { flexDirection: 'row', gap: Spacing.three, marginTop: Spacing.one },
});

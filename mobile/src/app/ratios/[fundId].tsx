import { useLocalSearchParams } from 'expo-router';
import { Fragment } from 'react';
import { StyleSheet, View } from 'react-native';

import { useFolioRatios, useRatios } from '@/api/queries';
import type { FundRatio } from '@/api/types';
import { Spacing } from '@/constants/theme';
import { formatDate } from '@/format/date';
import { AppText, Card, Divider, EmptyState, ErrorState, SkeletonCard } from '@/ui/primitives';
import { Screen } from '@/ui/screen';

/**
 * Every fund-level ratio the LP fund page's Ratios section shows (Default scenario), the latest value
 * of each with the date it is for. Reads the website's own GET /fund_ratios.json; the server's scope
 * returns only the fund's own rows and this LP's folio rows, never another investor's.
 */
export default function RatiosScreen() {
  const { fundId, name, master, commitmentId } = useLocalSearchParams<{ fundId: string; name?: string; master?: string; commitmentId?: string }>();
  const ratios = useRatios(Number(fundId), false);
  // This folio's own ratios (IRR, MOIC…) — the website's commitment page Ratios tab
  const folio = useFolioRatios(commitmentId ? Number(commitmentId) : undefined);

  return (
    <Screen back title="Ratios" subtitle={name} onRefresh={() => Promise.all([ratios.refetch(), folio.refetch()])} updatedAt={ratios.dataUpdatedAt}>
      {/* A feeder with no ratios of its own shows its master fund's, and says so (as the website does) */}
      {folio.data && folio.data.length > 0 ? (
        <>
          <AppText variant="bodyStrong">Your folio</AppText>
          <RatioList rows={folio.data} />
          <AppText variant="bodyStrong">Fund</AppText>
        </>
      ) : null}
      {master ? <AppText color="textSecondary">These ratios are reported for the master fund.</AppText> : null}
      {ratios.isPending ? <SkeletonCard lines={5} /> : ratios.isError ? (
        <ErrorState message={ratios.error.message} onRetry={() => ratios.refetch()} />
      ) : ratios.data.length === 0 ? (
        <EmptyState icon="trending" title="No ratios reported yet" />
      ) : (
        <RatioList rows={ratios.data} />
      )}
    </Screen>
  );
}

/** Ratio name and date on the left, the value as the fund reports it on the right */
function RatioList({ rows }: { rows: FundRatio[] }) {
  return (
    <Card>
      {rows.map((r, i) => (
        <Fragment key={r.id}>
          {i > 0 ? <Divider /> : null}
          <View style={styles.item}>
            <View style={styles.grow}>
              <AppText variant="bodyStrong">{r.name}</AppText>
              <AppText variant="caption" color="textSecondary">{r.end_date ? `as of ${formatDate(r.end_date)}` : ''}</AppText>
            </View>
            <AppText variant="bodyStrong" style={styles.tabular}>{r.display_value ?? '—'}</AppText>
          </View>
        </Fragment>
      ))}
    </Card>
  );
}

const styles = StyleSheet.create({
  grow: { flex: 1 },
  item: { flexDirection: 'row', alignItems: 'center', gap: Spacing.two, paddingVertical: Spacing.one },
  tabular: { fontVariant: ['tabular-nums'] },
});

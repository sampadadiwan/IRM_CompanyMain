import { useLocalSearchParams } from 'expo-router';
import { Fragment } from 'react';
import { StyleSheet, View } from 'react-native';

import { useUnits } from '@/api/queries';
import { Spacing } from '@/constants/theme';
import { formatDate } from '@/format/date';
import { AppText, Card, Divider, EmptyState, ErrorState, SkeletonCard } from '@/ui/primitives';
import { Screen } from '@/ui/screen';

/**
 * The units allotted to this folio — the LP fund page's Units section: each allotment's class,
 * quantity, date and reason, newest first. Reads the website's own GET /fund_units.json.
 */
export default function UnitsScreen() {
  const { commitmentId, name } = useLocalSearchParams<{ commitmentId: string; name?: string }>();
  const units = useUnits(Number(commitmentId));

  return (
    <Screen back title="Units" subtitle={name} onRefresh={() => units.refetch()} updatedAt={units.dataUpdatedAt}>
      {units.isPending ? <SkeletonCard lines={4} /> : units.isError ? (
        <ErrorState message={units.error.message} onRetry={() => units.refetch()} />
      ) : units.data.length === 0 ? (
        <EmptyState icon="wallet" title="No units allotted yet" />
      ) : (
        <Card>
          {units.data.map((u, i) => (
            <Fragment key={u.id}>
              {i > 0 ? <Divider /> : null}
              <View style={styles.item}>
                <View style={styles.grow}>
                  <AppText variant="bodyStrong">{u.unit_type ?? 'Units'}</AppText>
                  <AppText variant="caption" color="textSecondary">
                    {[u.issue_date ? formatDate(u.issue_date) : null, u.reason].filter(Boolean).join(' · ')}
                  </AppText>
                </View>
                <AppText variant="bodyStrong" style={styles.tabular}>
                  {Number(u.quantity).toLocaleString('en-IN', { maximumFractionDigits: 4 })}
                </AppText>
              </View>
            </Fragment>
          ))}
        </Card>
      )}
    </Screen>
  );
}

const styles = StyleSheet.create({
  grow: { flex: 1 },
  item: { flexDirection: 'row', alignItems: 'center', gap: Spacing.two, paddingVertical: Spacing.one },
  tabular: { fontVariant: ['tabular-nums'] },
});

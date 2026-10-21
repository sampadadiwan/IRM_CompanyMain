import { router } from 'expo-router';
import { Fragment } from 'react';
import { StyleSheet, View } from 'react-native';

import { useKycs } from '@/api/queries';
import { Spacing } from '@/constants/theme';
import { useFundManager } from '@/lib/fund-manager';
import { kycStatus } from '@/lib/kyc';
import { AppText, Card, Divider, EmptyState, ErrorState, Icon, Pressy, SkeletonCard, StatusPill } from '@/ui/primitives';
import { Screen } from '@/ui/screen';

/**
 * The LP's KYCs for the picked fund manager, each with where it stands. Reads the website's own
 * GET /investor_kycs.json (the server's scope: the LP's own KYCs). Status only — the app never shows
 * PAN or bank details; filling the form happens on the website.
 */
export default function KycListScreen() {
  const kycs = useKycs();
  const { fundManagerId } = useFundManager();
  // One fund manager at a time, as everywhere else in the app
  const rows = (kycs.data ?? []).filter((k) => fundManagerId == null || k.entity_id === fundManagerId);

  return (
    <Screen back title="KYC" onRefresh={() => kycs.refetch()} updatedAt={kycs.dataUpdatedAt}>
      {kycs.isPending ? <SkeletonCard lines={3} /> : kycs.isError ? (
        <ErrorState message={kycs.error.message} onRetry={() => kycs.refetch()} />
      ) : rows.length === 0 ? (
        <EmptyState icon="person.crop.circle" title="No KYC requested" message="Your fund manager hasn't asked for a KYC yet." />
      ) : (
        <Card>
          {rows.map((k, i) => (
            <Fragment key={k.id}>
              {i > 0 ? <Divider /> : null}
              <Pressy onPress={() => router.push({ pathname: '/kyc/[id]', params: { id: String(k.id) } })} accessibilityRole="button"
                accessibilityLabel={`${k.full_name ?? 'KYC'}, ${kycStatus(k)}`}>
                <View style={styles.item}>
                  <View style={styles.grow}>
                    <AppText variant="bodyStrong">{k.full_name ?? 'KYC'}</AppText>
                    <AppText variant="caption" color="textSecondary">{k.kyc_type}</AppText>
                  </View>
                  <StatusPill status={kycStatus(k)} />
                  <Icon name="chevron.right" />
                </View>
              </Pressy>
            </Fragment>
          ))}
        </Card>
      )}
    </Screen>
  );
}

const styles = StyleSheet.create({
  item: { flexDirection: 'row', alignItems: 'center', gap: Spacing.two, paddingVertical: Spacing.one },
  grow: { flex: 1 },
});

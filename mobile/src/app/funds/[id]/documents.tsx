import { router, useLocalSearchParams } from 'expo-router';
import { StyleSheet, View } from 'react-native';

import { useDocuments } from '@/api/queries';
import { Spacing } from '@/constants/theme';
import { formatDate } from '@/format/date';
import { ListCard } from '@/ui/list-card';
import { AppText, Button, Icon, Pressy } from '@/ui/primitives';
import { Screen } from '@/ui/screen';

/** Statements, notices and reports on this folio, newest first — the website fund page's Documents section */
export default function FundDocumentsScreen() {
  const { id, name } = useLocalSearchParams<{ id: string; name?: string }>();
  const docs = useDocuments({ commitmentId: Number(id) });
  const rows = docs.data?.pages.flatMap((pg) => pg.items);
  return (
    <Screen back title="Documents" subtitle={name} onRefresh={() => docs.refetch()} updatedAt={docs.dataUpdatedAt}>
      <ListCard query={{ ...docs, data: rows }} empty="No documents yet for this fund" render={(d) => (
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
      {docs.hasNextPage ? (
        <Button title="Show more" kind="secondary" loading={docs.isFetchingNextPage} onPress={() => docs.fetchNextPage()} />
      ) : null}
    </Screen>
  );
}

const styles = StyleSheet.create({
  grow: { flex: 1 },
  item: { flexDirection: 'row', alignItems: 'center', gap: Spacing.two, paddingVertical: Spacing.one },
});

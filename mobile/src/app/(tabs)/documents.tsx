import { router } from 'expo-router';
import { Fragment, useEffect, useState } from 'react';
import { Pressable, StyleSheet, TextInput, View } from 'react-native';

import { useDocuments } from '@/api/queries';
import { useFundManager } from '@/lib/fund-manager';
import { Radius, Spacing, TouchTarget } from '@/constants/theme';
import { formatDate } from '@/format/date';
import { useTheme } from '@/hooks/use-theme';
import { AppText, Button, Card, Divider, EmptyState, ErrorState, Icon, Pressy, SkeletonCard } from '@/ui/primitives';
import { FundManagerPicker } from '@/ui/fund-manager-picker';
import { Screen } from '@/ui/screen';

/**
 * The Documents tab (US-5): every document on the investor's own commitments, calls and
 * distributions, newest first, with search and a "To sign" filter. 25 per page (E19).
 */
export default function DocumentsScreen() {
  const theme = useTheme();
  const [text, setText] = useState('');
  const [q, setQ] = useState('');
  const [toSign, setToSign] = useState(false);
  // Only the selected fund manager's documents (lp-mobile-multi-site MF-H4)
  const { fundManagerId, ready } = useFundManager();
  const docs = useDocuments({ q, toSign, fundManagerId }, ready);

  // Search as you type, without a request per keystroke
  useEffect(() => {
    const t = setTimeout(() => setQ(text.trim()), 300);
    return () => clearTimeout(t);
  }, [text]);

  const rows = docs.data?.pages.flatMap((p) => p.items) ?? [];
  return (
    <Screen title="Documents" tabs onRefresh={() => docs.refetch()} updatedAt={docs.dataUpdatedAt}>
      <FundManagerPicker />
      <View style={[styles.search, { backgroundColor: theme.surface, borderColor: theme.border }]}>
        <Icon name="magnifyingglass" />
        <TextInput value={text} onChangeText={setText} placeholder="Search documents" placeholderTextColor={theme.textSecondary}
          style={[styles.input, { color: theme.text }]} accessibilityLabel="Search documents" autoCorrect={false} />
      </View>
      <View style={styles.chips}>
        <Chip label="All" active={!toSign} onPress={() => setToSign(false)} />
        <Chip label="To sign" active={toSign} onPress={() => setToSign(true)} />
      </View>

      {docs.isPending ? <SkeletonCard lines={5} /> : docs.isError ? (
        <ErrorState message={docs.error.message} onRetry={() => docs.refetch()} />
      ) : rows.length === 0 ? (
        <EmptyState icon="doc.text" title={toSign ? 'Nothing to sign' : q ? 'No matching documents' : 'No documents yet'}
          message={toSign ? "You're all caught up." : undefined} />
      ) : (
        <Card>
          {rows.map((d, i) => (
            <Fragment key={d.id}>
              {i > 0 ? <Divider /> : null}
              <Pressy onPress={() => router.push({ pathname: '/documents/[id]', params: { id: String(d.id) } })} accessibilityRole="button" accessibilityLabel={d.name}>
                <View style={styles.row}>
                  <Icon name="doc.text" />
                  <View style={styles.grow}>
                    <AppText variant="bodyStrong" numberOfLines={2}>{d.name}</AppText>
                    <AppText variant="caption" color="textSecondary">{OWNER_LABEL[d.owner_type] ?? 'Document'} · {formatDate(d.created_at)}</AppText>
                  </View>
                  <Icon name="chevron.right" />
                </View>
              </Pressy>
            </Fragment>
          ))}
        </Card>
      )}
      {docs.hasNextPage ? <Button title="Load more" kind="secondary" loading={docs.isFetchingNextPage} onPress={() => docs.fetchNextPage()} /> : null}
    </Screen>
  );
}

const OWNER_LABEL: Record<string, string> = {
  CapitalCommitment: 'Commitment', CapitalRemittance: 'Capital call', CapitalDistributionPayment: 'Distribution',
};

function Chip({ label, active, onPress }: { label: string; active: boolean; onPress: () => void }) {
  const theme = useTheme();
  return (
    <Pressable onPress={onPress} accessibilityRole="button" accessibilityState={{ selected: active }}
      style={[styles.chip, { backgroundColor: active ? theme.inverse : theme.surface }]}>
      <AppText variant="bodyStrong" color={active ? 'onInverse' : 'textSecondary'}>{label}</AppText>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  search: { flexDirection: 'row', alignItems: 'center', gap: Spacing.two, borderWidth: 0, borderRadius: Radius.pill, paddingHorizontal: Spacing.four, minHeight: TouchTarget + 8 },
  input: { flex: 1, fontSize: 16, minHeight: TouchTarget, fontFamily: 'Manrope_400Regular' },
  chips: { flexDirection: 'row', gap: Spacing.two },
  chip: { paddingHorizontal: Spacing.four, minHeight: 44, borderRadius: Radius.pill, justifyContent: 'center' },
  row: { flexDirection: 'row', alignItems: 'center', gap: Spacing.two, paddingVertical: Spacing.one },
  grow: { flex: 1, gap: 2 },
});

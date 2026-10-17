import { Fragment } from 'react';
import { Pressable, StyleSheet, View } from 'react-native';

import { useMarkAllRead, useMarkRead, useMe, useNotifications } from '@/api/queries';
import { Spacing, TouchTarget } from '@/constants/theme';
import { formatRelativeDay } from '@/format/date';
import { useTheme } from '@/hooks/use-theme';
import { openLink } from '@/lib/links';
import { AppText, Card, Divider, EmptyState, ErrorState, Icon, Pressy, SkeletonCard } from '@/ui/primitives';
import { Screen } from '@/ui/screen';

/**
 * The Alerts tab: the website bell's notifications, sharing its read state (H9, E25). Tapping an
 * alert marks it read and opens the item — an app screen, or the website page for anything the
 * app has no screen for (E15).
 */
export default function AlertsScreen() {
  const me = useMe();
  const alerts = useNotifications();
  const markRead = useMarkRead();
  const markAll = useMarkAllRead(me.data?.user.id);
  const rows = alerts.data ?? [];
  const unread = rows.filter((n) => !n.read_at).length;

  return (
    <Screen tabs onRefresh={() => alerts.refetch()} updatedAt={alerts.dataUpdatedAt}
      header={(
        <View style={styles.headerRow}>
          <AppText variant="title" accessibilityRole="header">Alerts</AppText>
          {unread > 0 ? (
            <Pressable onPress={() => markAll.mutate()} accessibilityRole="button" style={styles.link}>
              <AppText color="accent" variant="bodyStrong">Mark all read</AppText>
            </Pressable>
          ) : null}
        </View>
      )}>
      {alerts.isPending ? <SkeletonCard lines={5} /> : alerts.isError ? (
        <ErrorState message={alerts.error.message} onRetry={() => alerts.refetch()} />
      ) : rows.length === 0 ? (
        <EmptyState icon="bell" title="No alerts yet" message="Capital calls, documents and other updates from your fund managers appear here." />
      ) : (
        <Card>
          {rows.map((n, i) => (
            <Fragment key={n.id}>
              {i > 0 ? <Divider /> : null}
              <Pressy accessibilityRole="button" accessibilityLabel={`${n.read_at ? '' : 'Unread. '}${n.sender ?? ''}: ${n.message}`}
                onPress={() => {
                  if (!n.read_at) markRead.mutate(n.id);
                  openLink(n.link);
                }}>
                <AlertRow sender={n.sender} message={n.message} when={formatRelativeDay(n.created_at)} unread={!n.read_at} />
              </Pressy>
            </Fragment>
          ))}
        </Card>
      )}
    </Screen>
  );
}

function AlertRow({ sender, message, when, unread }: { sender: string | null; message: string; when: string; unread: boolean }) {
  const theme = useTheme();
  return (
    <View style={styles.row}>
      <View style={[styles.dot, { backgroundColor: unread ? theme.accent : 'transparent' }]} />
      <View style={styles.grow}>
        <View style={styles.top}>
          <AppText variant="caption" color="textSecondary" style={styles.grow} numberOfLines={1}>{sender}</AppText>
          <AppText variant="caption" color="textSecondary">{when}</AppText>
        </View>
        <AppText variant={unread ? 'bodyStrong' : 'body'} numberOfLines={3}>{message}</AppText>
      </View>
      <Icon name="chevron.right" />
    </View>
  );
}

const styles = StyleSheet.create({
  headerRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  link: { minHeight: TouchTarget, justifyContent: 'center' },
  row: { flexDirection: 'row', alignItems: 'center', gap: Spacing.two, paddingVertical: Spacing.one },
  dot: { width: 8, height: 8, borderRadius: 4 },
  grow: { flex: 1 },
  top: { flexDirection: 'row', gap: Spacing.two },
});

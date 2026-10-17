import { useNetInfo } from '@react-native-community/netinfo';
import { LinearGradient } from 'expo-linear-gradient';
import { router } from 'expo-router';
import { type ReactNode, useState } from 'react';
import { RefreshControl, ScrollView, StyleSheet, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { BottomTabInset, MaxContentWidth, Spacing } from '@/constants/theme';
import { formatDateTime } from '@/format/date';
import { useTheme } from '@/hooks/use-theme';
import { AppText, Icon, IconButton } from '@/ui/primitives';

/**
 * A scrolling screen with a large title, pull-to-refresh and the offline bar
 * ("Last updated HH:MM — offline", spec "Offline and errors"). Content is capped at a phone-ish
 * width so the web review build looks like the app.
 */
export function Screen({ title, subtitle, children, onRefresh, updatedAt, tabs = false, header, back = false, action }:
  { title?: string; subtitle?: string; children: ReactNode; onRefresh?: () => Promise<unknown>; updatedAt?: number; tabs?: boolean; header?: ReactNode; back?: boolean; action?: ReactNode }) {
  const theme = useTheme();
  const insets = useSafeAreaInsets();
  const [refreshing, setRefreshing] = useState(false);

  return (
    // The screen fades from a lighter graphite at the top to near-black at the bottom (reference)
    <LinearGradient colors={[theme.screenTop, theme.screenBottom]} style={styles.fill}>
    <ScrollView
      style={styles.fill}
      contentContainerStyle={[styles.content, { paddingTop: insets.top + Spacing.three, paddingBottom: insets.bottom + (tabs ? BottomTabInset : 0) + Spacing.five }]}
      refreshControl={onRefresh ? (
        <RefreshControl refreshing={refreshing} tintColor={theme.accent} onRefresh={async () => {
          setRefreshing(true);
          try { await onRefresh(); } finally { setRefreshing(false); }
        }} />
      ) : undefined}>
      <View style={styles.inner}>
        <OfflineBar updatedAt={updatedAt} />
        {back || action ? (
          // The reference's round back button (and an optional round action on the right)
          <View style={styles.nav}>
            {back ? <IconButton name="chevron.left" label="Back" onPress={() => (router.canGoBack() ? router.back() : router.replace('/'))} /> : <View />}
            {action}
          </View>
        ) : null}
        {header}
        {title ? <AppText variant="title" accessibilityRole="header">{title}</AppText> : null}
        {subtitle ? <AppText color="textSecondary">{subtitle}</AppText> : null}
        {children}
      </View>
    </ScrollView>
    </LinearGradient>
  );
}

export function OfflineBar({ updatedAt }: { updatedAt?: number }) {
  const theme = useTheme();
  const net = useNetInfo();
  if (net.isConnected !== false) return null;
  return (
    <View style={[styles.offline, { backgroundColor: theme.warningSoft }]} accessibilityLiveRegion="polite">
      <Icon name="wifi.slash" color="warning" />
      <AppText variant="caption" color="warning">
        {updatedAt ? `Last updated ${formatDateTime(new Date(updatedAt)).split(' ').pop()} — offline` : "You're offline"}
      </AppText>
    </View>
  );
}

export function Section({ title, children, action }: { title: string; children: ReactNode; action?: ReactNode }) {
  return (
    <View style={styles.section}>
      <View style={styles.sectionHead}>
        <AppText variant="heading" accessibilityRole="header">{title}</AppText>
        {action}
      </View>
      {children}
    </View>
  );
}

const styles = StyleSheet.create({
  fill: { flex: 1 },
  content: { flexGrow: 1, paddingHorizontal: Spacing.three + 4 },
  inner: { width: '100%', maxWidth: MaxContentWidth, alignSelf: 'center', gap: Spacing.three + 2 },
  offline: { flexDirection: 'row', alignItems: 'center', gap: Spacing.two, padding: Spacing.two, borderRadius: 999, paddingHorizontal: Spacing.three },
  section: { gap: Spacing.two, marginTop: Spacing.two },
  nav: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  sectionHead: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
});

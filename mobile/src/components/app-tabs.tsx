import Ionicons from '@expo/vector-icons/Ionicons';
import { Tabs } from 'expo-router';
import type { ComponentProps } from 'react';
import { Pressable, StyleSheet, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { useMe } from '@/api/queries';
import { TouchTarget } from '@/constants/theme';
import { useTheme } from '@/hooks/use-theme';

/**
 * The four tabs — Home, Documents, Alerts, Profile — and nothing else (proposal "only the key
 * screens"), as a full-width bar docked at the bottom: round icon buttons spread evenly, the
 * active one a white circle (product owner, 2026-10-13). Same bar on iOS, Android and the web review build. Alerts shows an
 * orange dot while anything is unread (the same count as the website's bell).
 */
const TABS: Record<string, { icon: keyof typeof Ionicons.glyphMap; label: string }> = {
  index: { icon: 'home-outline', label: 'Home' },
  documents: { icon: 'document-text-outline', label: 'Documents' },
  alerts: { icon: 'notifications-outline', label: 'Alerts' },
  profile: { icon: 'person-outline', label: 'Profile' },
};

/** expo-router vendors react-navigation; take the tab bar's props from its own Tabs type */
type BottomTabBarProps = Parameters<NonNullable<ComponentProps<typeof Tabs>['tabBar']>>[0];

export default function AppTabs() {
  return (
    <Tabs screenOptions={{ headerShown: false }} tabBar={(props) => <FloatingTabBar {...props} />}>
      <Tabs.Screen name="index" options={{ title: 'Home' }} />
      <Tabs.Screen name="documents" options={{ title: 'Documents' }} />
      <Tabs.Screen name="alerts" options={{ title: 'Alerts' }} />
      <Tabs.Screen name="profile" options={{ title: 'Profile' }} />
    </Tabs>
  );
}

function FloatingTabBar({ state, navigation }: BottomTabBarProps) {
  const theme = useTheme();
  const insets = useSafeAreaInsets();
  const { data: me } = useMe();
  const unread = me?.unread_notifications ?? 0;

  return (
    <View style={[styles.wrap, { backgroundColor: theme.surfaceAlt, paddingBottom: Math.max(insets.bottom, 10) }]}>
      <View style={styles.bar} accessibilityRole="tablist">
        {state.routes.map((route, index) => {
          const tab = TABS[route.name];
          if (!tab) return null;
          const focused = state.index === index;
          return (
            <Pressable key={route.key} accessibilityRole="tab" accessibilityState={{ selected: focused }}
              accessibilityLabel={route.name === 'alerts' && unread ? `${tab.label}, ${unread} unread` : tab.label}
              onPress={() => {
                const event = navigation.emit({ type: 'tabPress', target: route.key, canPreventDefault: true });
                if (!focused && !event.defaultPrevented) navigation.navigate(route.name);
              }}
              style={[styles.button, focused && { backgroundColor: theme.inverse }]}>
              <Ionicons name={tab.icon} size={22} color={focused ? theme.onInverse : theme.text} />
              {route.name === 'alerts' && unread > 0 ? (
                <View style={[styles.dot, { backgroundColor: theme.accent, borderColor: focused ? theme.inverse : theme.surfaceAlt }]} />
              ) : null}
            </Pressable>
          );
        })}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: { position: 'absolute', left: 0, right: 0, bottom: 0, borderTopLeftRadius: 28, borderTopRightRadius: 28, paddingTop: 10, shadowColor: '#000', shadowOpacity: 0.35, shadowRadius: 18, shadowOffset: { width: 0, height: -4 }, elevation: 10 },
  bar: { flexDirection: 'row', justifyContent: 'space-around', alignItems: 'center', width: '100%', maxWidth: 640, alignSelf: 'center' },
  button: { width: TouchTarget + 12, height: TouchTarget + 12, borderRadius: 999, alignItems: 'center', justifyContent: 'center' },
  dot: { position: 'absolute', top: 14, right: 15, width: 10, height: 10, borderRadius: 5, borderWidth: 2 },
});

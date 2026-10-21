import { useQuery } from '@tanstack/react-query';
import { useState } from 'react';
import { Pressable, StyleSheet, TextInput, View } from 'react-native';

import { api } from '@/api/client';
import {
  customEnvironment, DEFAULT_ENVIRONMENT, DEV_API_URL, ENVIRONMENTS, SHOW_TEST_ENVIRONMENTS,
  type Environment, type EnvironmentId, type Region,
} from '@/api/config';
import { useAuth } from '@/auth/session';
import { Radius, Spacing, TouchTarget } from '@/constants/theme';
import { useTheme } from '@/hooks/use-theme';
import { AppText, Button, Card, ErrorState, Icon, Segmented, SkeletonCard } from '@/ui/primitives';
import { Screen } from '@/ui/screen';

/**
 * A2 — where the account lives: an environment and one of its regions (lp-mobile-multi-site
 * design card ①). Investors see only CapHive (production) and its regions. A long press on the
 * CapHive name reveals Staging and a typed-in address for the team (MS-H1); a staging build
 * starts with them revealed.
 */
export default function RegionScreen() {
  const { chooseSite } = useAuth();
  const theme = useTheme();
  const [showTest, setShowTest] = useState(SHOW_TEST_ENVIRONMENTS);
  const [envId, setEnvId] = useState<EnvironmentId>(DEFAULT_ENVIRONMENT);
  const [customUrl, setCustomUrl] = useState(DEV_API_URL ?? 'http://');
  const [customEnv, setCustomEnv] = useState<Environment | null>(null);

  const env = envId === 'custom' ? customEnv : ENVIRONMENTS.find((e) => e.id === envId) ?? ENVIRONMENTS[0];
  const sites = useSites(env);

  return (
    <Screen>
      <View style={styles.brand}>
        <Pressable onLongPress={() => setShowTest(true)} delayLongPress={800} accessibilityRole="header"
          accessibilityHint="Long press to show test environments">
          <AppText variant="title">CapHive</AppText>
        </Pressable>
        <AppText color="textSecondary">Your investments, capital calls and documents — on your phone.</AppText>
      </View>

      {showTest ? (
        <Segmented<EnvironmentId> value={envId} onChange={setEnvId}
          options={[{ value: 'production', label: 'CapHive' }, { value: 'staging', label: 'Staging' }, { value: 'custom', label: 'Custom' }]} />
      ) : null}

      {envId === 'custom' ? (
        <>
          <TextInput value={customUrl} onChangeText={setCustomUrl} autoCapitalize="none" autoCorrect={false} keyboardType="url"
            placeholder="http://192.168.1.20:3000" placeholderTextColor={theme.textSecondary} accessibilityLabel="Server address"
            style={[styles.input, { color: theme.text, backgroundColor: theme.surface }]} />
          <Button title="Connect" kind="secondary" disabled={!/^https?:\/\/.+/.test(customUrl.trim())}
            onPress={() => setCustomEnv(customEnvironment(customUrl))} />
        </>
      ) : null}

      {env ? (
        <>
          <AppText variant="heading" accessibilityRole="header">Where is your account?</AppText>
          {sites.isPending ? <SkeletonCard lines={2} /> : !sites.data?.length ? (
            <ErrorState message="Can't reach this server. Check the address and your connection." onRetry={() => sites.refetch()} />
          ) : sites.data.map((region) => (
            <Card key={region.url} onPress={() => chooseSite({ ...region, env: env.id })} accessibilityLabel={`Choose ${region.label}`}>
              <View style={styles.row}>
                <View style={styles.grow}>
                  <AppText variant="bodyStrong">{region.label}</AppText>
                  {env.id !== 'production' ? <AppText variant="caption" color="textSecondary">{region.url}</AppText> : null}
                </View>
                <Icon name="chevron.right" />
              </View>
            </Card>
          ))}
          <AppText variant="caption" color="textSecondary">
            Pick the site you sign in to on the web. You can switch region later from your profile.
          </AppText>
        </>
      ) : null}
    </Screen>
  );
}

/**
 * The environment's regions, from its own server (GET /api/mobile/v1/sites). An older server
 * without that endpoint answers 404, so the environment's built-in list is used instead.
 */
function useSites(env: Environment | null) {
  return useQuery({
    queryKey: ['sites', env?.url],
    enabled: env != null,
    retry: false,
    queryFn: () => api<{ sites: Region[] }>('/api/mobile/v1/sites', { auth: false, base: env!.url })
      .then((res) => res.sites)
      .catch(() => env!.fallbackSites),
  });
}

const styles = StyleSheet.create({
  brand: { gap: Spacing.two, marginTop: Spacing.five, marginBottom: Spacing.four },
  row: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', minHeight: 32 },
  grow: { flex: 1, gap: 2 },
  input: { minHeight: TouchTarget + 10, borderRadius: Radius.pill, paddingHorizontal: Spacing.four, fontSize: 16, fontFamily: 'Manrope_400Regular' },
});

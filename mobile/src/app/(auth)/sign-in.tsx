import * as WebBrowser from 'expo-web-browser';
import { useState } from 'react';
import { Pressable, StyleSheet, TextInput, View } from 'react-native';

import { ApiError, currentRegion } from '@/api/client';
import { REGIONS } from '@/api/config';
import { useAuth } from '@/auth/session';
import { Radius, Spacing, TouchTarget } from '@/constants/theme';
import { useTheme } from '@/hooks/use-theme';
import { AppText, Button } from '@/ui/primitives';
import { Screen } from '@/ui/screen';

/** A3 — email and password; the server answers with a session or a code challenge */
export default function SignInScreen() {
  const { signIn, changeRegion } = useAuth();
  const theme = useTheme();
  const region = currentRegion();
  const otherRegion = REGIONS.find((r) => r.code !== region?.code);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [showRegionHint, setShowRegionHint] = useState(false);
  const [busy, setBusy] = useState(false);

  const submit = async () => {
    setBusy(true);
    setError(null);
    setShowRegionHint(false);
    try {
      await signIn(email, password);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Something went wrong. Please try again.');
      // X14 — the same answer as a wrong password, plus a hint about the other site
      setShowRegionHint(e instanceof ApiError && e.code === 'invalid_credentials');
    } finally {
      setBusy(false);
    }
  };

  const input = [styles.input, { borderColor: theme.border, color: theme.text, backgroundColor: theme.surface }];

  return (
    <Screen title="Sign in" subtitle="Use the same email and password as the CapHive website.">
      <View style={styles.region}>
        <AppText color="textSecondary">Region: <AppText variant="bodyStrong">{region?.label}</AppText></AppText>
        <Pressable onPress={changeRegion} accessibilityRole="button" style={styles.link}>
          <AppText color="accent" variant="bodyStrong">Change</AppText>
        </Pressable>
      </View>

      <TextInput style={input} placeholder="Email" placeholderTextColor={theme.textSecondary} value={email} onChangeText={setEmail}
        autoCapitalize="none" autoComplete="email" keyboardType="email-address" textContentType="username" accessibilityLabel="Email" />
      <TextInput style={input} placeholder="Password" placeholderTextColor={theme.textSecondary} value={password} onChangeText={setPassword}
        secureTextEntry autoCapitalize="none" autoCorrect={false} spellCheck={false} autoComplete="current-password" textContentType="password" accessibilityLabel="Password" onSubmitEditing={submit} />

      {error ? (
        <View style={[styles.error, { backgroundColor: theme.dangerSoft }]} accessibilityLiveRegion="polite">
          <AppText color="danger">{error}</AppText>
          {showRegionHint && otherRegion ? (
            <Pressable onPress={changeRegion} accessibilityRole="button">
              <AppText color="danger">Is your account on the {otherRegion.label} site? <AppText color="danger" variant="bodyStrong">Switch region</AppText></AppText>
            </Pressable>
          ) : null}
        </View>
      ) : null}

      <Button title="Sign in" onPress={submit} loading={busy} disabled={!email || !password} />

      <View style={styles.links}>
        <Pressable style={styles.link} accessibilityRole="link"
          onPress={() => region && WebBrowser.openBrowserAsync(`${region.url}/users/password/new`)}>
          <AppText color="accent">Forgot password?</AppText>
        </Pressable>
      </View>
    </Screen>
  );
}

const styles = StyleSheet.create({
  region: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  input: { minHeight: TouchTarget + 10, borderWidth: 0, borderRadius: Radius.pill, paddingHorizontal: Spacing.four, fontSize: 16, fontFamily: 'Manrope_400Regular' },
  error: { padding: Spacing.three, borderRadius: 20, gap: Spacing.two },
  links: { flexDirection: 'row', justifyContent: 'center' },
  link: { minHeight: TouchTarget, justifyContent: 'center', paddingHorizontal: Spacing.two },
});

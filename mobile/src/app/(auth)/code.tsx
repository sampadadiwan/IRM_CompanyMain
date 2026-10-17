import { useState } from 'react';
import { Pressable, StyleSheet, TextInput, View } from 'react-native';

import { ApiError } from '@/api/client';
import { useAuth } from '@/auth/session';
import { Spacing, TouchTarget } from '@/constants/theme';
import { useTheme } from '@/hooks/use-theme';
import { AppText, Button } from '@/ui/primitives';
import { Screen } from '@/ui/screen';

const WHERE: Record<string, string> = {
  authenticator: 'Enter the 6-digit code from your authenticator app.',
  sms: 'Enter the 6-digit code we texted to your phone.',
  whatsapp: 'Enter the 6-digit code we sent on WhatsApp.',
};

/** A4 — the same two-factor code as the website; three tries, then sign in again (E1, X2) */
export default function CodeScreen() {
  const { challenge, verifyCode, resendCode, signOut } = useAuth();
  const theme = useTheme();
  const [code, setCode] = useState('');
  const [message, setMessage] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const canResend = challenge?.method === 'sms' || challenge?.method === 'whatsapp';

  const submit = async () => {
    setBusy(true);
    setMessage(null);
    try {
      await verifyCode(code);
    } catch (e) {
      const left = e instanceof ApiError ? Number(e.body.attempts_left ?? 0) : 0;
      setMessage(left > 0 ? `${e instanceof Error ? e.message : ''} ${left} ${left === 1 ? 'attempt' : 'attempts'} left.` : e instanceof Error ? e.message : '');
      setCode('');
    } finally {
      setBusy(false);
    }
  };

  return (
    <Screen title="Enter your code" subtitle={WHERE[challenge?.method ?? 'authenticator']}>
      <TextInput
        style={[styles.code, { borderColor: theme.border, color: theme.text, backgroundColor: theme.surface }]}
        value={code} onChangeText={(v) => setCode(v.replace(/[^0-9]/g, '').slice(0, 6))}
        keyboardType="number-pad" textContentType="oneTimeCode" autoComplete="one-time-code" autoFocus
        accessibilityLabel="Six digit code" onSubmitEditing={submit} placeholder="••••••" placeholderTextColor={theme.textSecondary} />
      {message ? <AppText color="danger" accessibilityLiveRegion="polite">{message}</AppText> : null}
      <Button title="Verify" onPress={submit} loading={busy} disabled={code.length < 6} />
      <View style={styles.links}>
        {canResend ? (
          <Pressable style={styles.link} accessibilityRole="button" onPress={async () => {
            try { await resendCode(); setMessage('A new code is on its way.'); } catch (e) { setMessage(e instanceof Error ? e.message : null); }
          }}>
            <AppText color="accent">Send a new code</AppText>
          </Pressable>
        ) : null}
        <Pressable style={styles.link} accessibilityRole="button" onPress={signOut}>
          <AppText color="textSecondary">Back</AppText>
        </Pressable>
      </View>
    </Screen>
  );
}

const styles = StyleSheet.create({
  code: { minHeight: 64, borderWidth: 0, borderRadius: 24, fontSize: 28, letterSpacing: 12, fontFamily: 'Manrope_300Light', textAlign: 'center', fontVariant: ['tabular-nums'] },
  links: { flexDirection: 'row', justifyContent: 'space-between' },
  link: { minHeight: TouchTarget, justifyContent: 'center', paddingHorizontal: Spacing.two },
});

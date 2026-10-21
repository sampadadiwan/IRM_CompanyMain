import { useLocalSearchParams } from 'expo-router';
import { useState } from 'react';
import { Alert, StyleSheet, TextInput, View } from 'react-native';

import { useKycs, useRequestKycUpdates } from '@/api/queries';
import { Radius, Spacing } from '@/constants/theme';
import { useTheme } from '@/hooks/use-theme';
import { kycStatus, kycToComplete } from '@/lib/kyc';
import { openWebsitePage } from '@/lib/links';
import { AppText, Button, Card, ErrorState, Row, SkeletonCard, StatusPill } from '@/ui/primitives';
import { Screen } from '@/ui/screen';

/**
 * One KYC's status, and the one thing the investor can do next:
 *   - still open → Complete KYC, the website's form in the in-app browser (forms stay on the website);
 *   - submitted or verified → Updates required, the website's own request to the GP
 *     (investor_kycs#send_notification, allowed only then — InvestorKycPolicy#send_notification?).
 */
export default function KycScreen() {
  const theme = useTheme();
  const { id } = useLocalSearchParams<{ id: string }>();
  const kycs = useKycs();
  const request = useRequestKycUpdates();
  const [message, setMessage] = useState('');

  if (kycs.isPending) return <Screen back><SkeletonCard lines={4} /></Screen>;
  if (kycs.isError) return <Screen back><ErrorState message={kycs.error.message} onRetry={() => kycs.refetch()} /></Screen>;
  const k = kycs.data.find((row) => row.id === Number(id));
  if (!k) return <Screen back><ErrorState message="This KYC is no longer available." onRetry={() => kycs.refetch()} /></Screen>;

  // Confirm first: the GP is notified straight away
  const sendRequest = () => Alert.alert('Ask for changes?', `${k.full_name ?? 'Your KYC'} will be reopened for updates once your fund manager responds.`, [
    { text: 'Cancel', style: 'cancel' },
    {
      text: 'Send',
      onPress: () => request.mutate({ id: k.id, message }, {
        onSuccess: () => { setMessage(''); Alert.alert('Request sent', 'Your fund manager will get back to you.'); },
        onError: (e) => Alert.alert("Couldn't send the request", e instanceof Error ? e.message : 'Please try again.'),
      }),
    },
  ]);

  return (
    <Screen back title={k.full_name ?? 'KYC'} subtitle={k.kyc_type} onRefresh={() => kycs.refetch()} updatedAt={kycs.dataUpdatedAt}>
      <Card>
        <View style={styles.statusRow}>
          <AppText color="textSecondary">Status</AppText>
          <StatusPill status={kycStatus(k)} />
        </View>
        <Row label="Documents" value={k.docs_completed ? 'Complete' : 'Outstanding'} />
      </Card>

      {kycToComplete(k) ? (
        <Button title="Complete KYC" icon="open" onPress={() => openWebsitePage(`/investor_kycs/${k.id}/edit`)} />
      ) : k.can_request_updates ? (
        <>
          <AppText color="textSecondary">Something changed? Ask your fund manager to reopen this KYC.</AppText>
          <TextInput value={message} onChangeText={setMessage} placeholder="What needs updating (optional)" multiline
            placeholderTextColor={theme.textSecondary} accessibilityLabel="What needs updating"
            style={[styles.input, { color: theme.text, backgroundColor: theme.surface }]} />
          <Button title="Updates required" kind="secondary" loading={request.isPending} onPress={sendRequest} />
        </>
      ) : (
        <AppText color="textSecondary">Your fund manager hasn&apos;t sent this KYC to you yet.</AppText>
      )}
    </Screen>
  );
}

const styles = StyleSheet.create({
  statusRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  // The Documents search box's look (no border, the theme surface), taller for a sentence
  input: { minHeight: 80, borderWidth: 0, borderRadius: Radius.tile, paddingHorizontal: Spacing.four, paddingVertical: Spacing.three, textAlignVertical: 'top' },
});

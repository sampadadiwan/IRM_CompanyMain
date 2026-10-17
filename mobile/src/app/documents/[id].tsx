import { useNetInfo } from '@react-native-community/netinfo';
import { useLocalSearchParams } from 'expo-router';
import { Platform, Share, StyleSheet, View } from 'react-native';

import { useDocument } from '@/api/queries';
import { Spacing } from '@/constants/theme';
import { formatDate } from '@/format/date';
import { openDocumentFile, openSigning } from '@/lib/links';
import { AppText, Button, Card, ErrorState, Icon, IconButton, SkeletonCard, StatusPill } from '@/ui/primitives';
import { Screen } from '@/ui/screen';

/**
 * The Document screen (US-5). One primary action: Sign when this user still has to sign,
 * otherwise Open. Opening it here already recorded "viewed by" on the website (H7).
 *   Digio     → its signing page in the app, then the status refreshes (H18)
 *   DocuSign  → signed from DocuSign's own email (E21)
 * Sign is disabled offline (spec "Document screen and signing").
 */
export default function DocumentScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const doc = useDocument(Number(id));
  const net = useNetInfo();
  const offline = net.isConnected === false;

  if (doc.isPending) return <Screen back><SkeletonCard lines={3} /></Screen>;
  if (doc.isError) return <Screen back><ErrorState message={doc.error.message} onRetry={() => doc.refetch()} /></Screen>;

  const d = doc.data;
  const signed = d.signature_status === 'signed';
  return (
    <Screen back title={d.name} subtitle={formatDate(d.created_at)} onRefresh={() => doc.refetch()} updatedAt={doc.dataUpdatedAt}
      action={Platform.OS !== 'web' ? (
        <IconButton name="square.and.arrow.up" label="Share" onPress={() => Share.share({ title: d.name, message: d.name, url: d.s3_url })} />
      ) : undefined}>
      {d.signature_status ? (
        <Card>
          <View style={styles.row}>
            <AppText color="textSecondary">Your signature</AppText>
            <StatusPill status={signed ? 'Signed' : 'To sign'} />
          </View>
        </Card>
      ) : null}

      {d.sign_action === 'digio_url' && d.sign_url ? (
        <Button title="Sign" icon="signature" disabled={offline}
          accessibilityHint="Opens Digio's signing page"
          onPress={async () => {
            await openSigning(d.sign_url!);
            await doc.refetch();
          }} />
      ) : d.sign_action === 'docusign_email' ? (
        <Card>
          <View style={styles.row}>
            <Icon name="signature" color="warning" />
            <View style={styles.grow}>
              <AppText variant="bodyStrong">Sign in DocuSign email</AppText>
              <AppText color="textSecondary">Open the email from DocuSign on this phone to sign.</AppText>
            </View>
          </View>
        </Card>
      ) : null}

      <Button title="Open document" kind={d.sign_action ? 'secondary' : 'primary'} icon="doc.text" onPress={() => openDocumentFile(d.s3_url)} />
    </Screen>
  );
}

const styles = StyleSheet.create({
  row: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: Spacing.two },
  grow: { flex: 1, gap: 2 },
});

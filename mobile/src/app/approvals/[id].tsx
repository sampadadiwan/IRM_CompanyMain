import { router, useLocalSearchParams } from 'expo-router';
import { Fragment, useState } from 'react';
import { Alert, StyleSheet, View } from 'react-native';

import { useApproval, useRespondToApproval } from '@/api/queries';
import { Spacing } from '@/constants/theme';
import { formatDate } from '@/format/date';
import { openWebsitePage } from '@/lib/links';
import { AppText, Button, Card, Divider, ErrorState, Icon, Pressy, Segmented, SkeletonCard, StatusPill } from '@/ui/primitives';
import { Screen } from '@/ui/screen';

/**
 * The Approval screen: a GP's request for the investor's consent, answered in the app. Reads the
 * website's own GET /approval_responses/:id.json and answers through its approval_responses#approve,
 * which enforces the same ownership and due-date rules as the website (ApprovalResponsePolicy#approve?).
 * When the GP added custom fields to the response, the website's form opens instead — the app does
 * not re-build custom forms.
 */
export default function ApprovalScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const response = useApproval(Number(id));
  const respond = useRespondToApproval(Number(id));
  const [choice, setChoice] = useState<string | null>(null);

  if (response.isPending) return <Screen back><SkeletonCard lines={5} /></Screen>;
  if (response.isError) {
    return <Screen back><ErrorState message={response.error.message} onRetry={() => response.refetch()} /></Screen>;
  }

  const r = response.data;
  const a = r.approval;
  // Answerable: still Pending and not past the due date
  const answerable = r.status === 'Pending' && a.open;
  const picked = choice ?? a.response_options[0];

  // Confirm first: an answer is registered with the GP straight away
  const submit = () => {
    if (!picked) return;
    Alert.alert(`Submit "${picked}"?`, `Your response to "${a.title}" for ${r.owner_label} goes to ${a.entity_name}.`, [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Submit',
        onPress: () => respond.mutate(picked, {
          onError: (e) => Alert.alert("Couldn't submit your response", e instanceof Error ? e.message : 'Please try again.'),
        }),
      },
    ]);
  };

  return (
    <Screen back title={a.title} subtitle={a.entity_name} onRefresh={() => response.refetch()} updatedAt={response.dataUpdatedAt}>
      <Card>
        <View style={styles.statusRow}>
          <AppText color="textSecondary">{a.due_date ? `Due by ${formatDate(a.due_date)}` : 'No due date'}</AppText>
          <StatusPill status={r.status} />
        </View>
        {a.agreements_reference ? <AppText>{a.agreements_reference}</AppText> : null}
        <AppText variant="caption" color="textSecondary">For {r.owner_label}</AppText>
      </Card>

      {/* The approval's documents, opened in the app's document viewer */}
      {r.documents.length > 0 ? (
        <Card>
          {r.documents.map((d, i) => (
            <Fragment key={d.id}>
              {i > 0 ? <Divider /> : null}
              <Pressy onPress={() => router.push({ pathname: '/documents/[id]', params: { id: String(d.id) } })} accessibilityRole="button" accessibilityLabel={d.name}>
                <View style={styles.item}>
                  <Icon name="doc.text" />
                  <AppText style={styles.grow}>{d.name}</AppText>
                  <Icon name="chevron.right" />
                </View>
              </Pressy>
            </Fragment>
          ))}
        </Card>
      ) : null}

      {!answerable ? (
        // Answered, or past the due date: read-only
        <Card>
          <AppText color="textSecondary">
            {r.status !== 'Pending'
              ? `You responded "${r.status}"${r.responded_at ? ` on ${formatDate(r.responded_at)}` : ''}.`
              : 'This approval is past its due date and can no longer be answered.'}
          </AppText>
        </Card>
      ) : r.needs_form ? (
        // E: the GP asks for more than a yes/no — their custom fields live on the website's form
        <>
          <AppText color="textSecondary">This response asks for a few more details.</AppText>
          <Button title="Respond on the website" icon="open" onPress={() => openWebsitePage(`/approvals/${a.id}`)} />
        </>
      ) : (
        <>
          <AppText variant="bodyStrong">Your response</AppText>
          <Segmented<string> value={picked ?? ''} onChange={setChoice}
            options={a.response_options.map((o) => ({ value: o, label: o }))} />
          <Button title="Submit response" loading={respond.isPending} onPress={submit} />
        </>
      )}
    </Screen>
  );
}

const styles = StyleSheet.create({
  statusRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  item: { flexDirection: 'row', alignItems: 'center', gap: Spacing.two, paddingVertical: Spacing.one },
  grow: { flex: 1 },
});

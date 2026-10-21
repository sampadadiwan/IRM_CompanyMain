import { Fragment, useState } from 'react';
import { Modal, Pressable, StyleSheet, View } from 'react-native';

import { Spacing, TouchTarget } from '@/constants/theme';
import { useFundManager } from '@/lib/fund-manager';
import { AppText, Card, Divider, Icon, Pressy } from '@/ui/primitives';

/**
 * The fund manager picker at the top of Home, Documents and Alerts (lp-mobile-multi-site design
 * card ③) — the website's GP dropdown. One fund manager is always selected; with only one there is
 * nothing to pick, so its name is shown as a plain label (MF-E3).
 *
 * Deliberately quiet: one line of grey caption text with a small chevron, no box — the picked
 * fund manager's logo in Home's top bar carries the branding. The tap area is still a full
 * touch target through hitSlop.
 */
// The caption line is ~18pt tall; pad it to the 44pt touch target
const HIT_SLOP = { top: (TouchTarget - 18) / 2, bottom: (TouchTarget - 18) / 2, left: Spacing.two, right: Spacing.two };

export function FundManagerPicker() {
  const { fundManagers, fundManagerId, choose } = useFundManager();
  const [open, setOpen] = useState(false);
  const current = fundManagers.find((f) => f.id === fundManagerId);
  if (!current) return null;

  if (fundManagers.length === 1) {
    return (
      <AppText variant="caption" color="textSecondary" numberOfLines={1}>{current.name}</AppText>
    );
  }

  return (
    <>
      {/* Small to look at, full-size to hit: hitSlop pads the caption line out to a touch target */}
      <Pressable onPress={() => setOpen(true)} accessibilityRole="button" hitSlop={HIT_SLOP}
        accessibilityLabel={`Fund manager: ${current.name}. Change fund manager`}
        style={({ pressed }) => [styles.trigger, pressed && styles.pressed]}>
        <AppText variant="caption" color="textSecondary" numberOfLines={1} style={styles.shrink}>{current.name}</AppText>
        <Icon name="chevron.down" size={12} />
      </Pressable>

      <Modal visible={open} transparent animationType="fade" onRequestClose={() => setOpen(false)}>
        <Pressable style={styles.backdrop} onPress={() => setOpen(false)} accessibilityLabel="Close">
          <Pressable style={styles.sheet} onPress={() => {}}>
            <Card>
              <AppText variant="heading" accessibilityRole="header">Fund manager</AppText>
              {fundManagers.map((f, i) => (
                <Fragment key={f.id}>
                  {i > 0 ? <Divider /> : null}
                  <Pressy accessibilityRole="button" accessibilityState={{ selected: f.id === fundManagerId }}
                    accessibilityLabel={f.name}
                    onPress={() => { choose(f.id); setOpen(false); }}>
                    <View style={styles.option}>
                      <AppText style={styles.grow} variant={f.id === fundManagerId ? 'bodyStrong' : 'body'}>{f.name}</AppText>
                      {f.id === fundManagerId ? <Icon name="checkmark" color="accent" /> : null}
                    </View>
                  </Pressy>
                </Fragment>
              ))}
            </Card>
          </Pressable>
        </Pressable>
      </Modal>
    </>
  );
}

const styles = StyleSheet.create({
  trigger: { flexDirection: 'row', alignItems: 'center', gap: 4, alignSelf: 'flex-start', maxWidth: '100%' },
  pressed: { opacity: 0.75 },
  shrink: { flexShrink: 1 },
  grow: { flex: 1 },
  backdrop: { flex: 1, backgroundColor: 'rgba(0,0,0,0.55)', justifyContent: 'center', padding: Spacing.four },
  sheet: { width: '100%', maxWidth: 480, alignSelf: 'center' },
  option: { flexDirection: 'row', alignItems: 'center', minHeight: TouchTarget },
});

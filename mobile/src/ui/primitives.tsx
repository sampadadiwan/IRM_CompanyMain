import Ionicons from '@expo/vector-icons/Ionicons';
import * as Haptics from 'expo-haptics';
import { LinearGradient } from 'expo-linear-gradient';
import { useEffect, useState, type ReactNode } from 'react';
import {
  ActivityIndicator, Animated, Platform, Pressable, StyleSheet, Text, View,
  type PressableProps, type StyleProp, type TextProps, type TextStyle, type ViewStyle,
} from 'react-native';

import { Radius, Spacing, TouchTarget, Type, type ThemeColor } from '@/constants/theme';
import { useTheme } from '@/hooks/use-theme';

/**
 * The app's building blocks, in the chosen look (constants/theme.ts): graphite cards with large
 * radii, pill buttons, white "selected" pills, round icon buttons, light big numerals and CapHive
 * orange as the one accent. Every screen is made of these, so the look stays one system
 * (proposal "UI/UX principles"): one primary action per screen, status = icon + label + colour,
 * skeletons instead of spinners.
 */

type Variant = keyof typeof Type;

export function AppText({ variant = 'body', color = 'text', style, ...rest }: TextProps & { variant?: Variant; color?: ThemeColor }) {
  const theme = useTheme();
  return <Text {...rest} style={[Type[variant] as TextStyle, { color: theme[color] }, style]} maxFontSizeMultiplier={1.6} />;
}

export function Card({ children, style, onPress, accessibilityLabel, tone = 'surface' }:
  { children: ReactNode; style?: StyleProp<ViewStyle>; onPress?: () => void; accessibilityLabel?: string; tone?: 'surface' | 'surfaceAlt' }) {
  const theme = useTheme();
  // A soft top-to-bottom sheen and a faint light edge give the card depth, as in the reference
  const colors = tone === 'surfaceAlt' ? [theme.surfaceAlt, theme.surface] as const : [theme.cardTop, theme.cardBottom] as const;
  const body = (
    <LinearGradient colors={colors} start={{ x: 0, y: 0 }} end={{ x: 0.4, y: 1 }}
      style={[styles.card, { borderColor: theme.hairline }, style]}>
      {children}
    </LinearGradient>
  );
  if (!onPress) return body;
  return (
    <Pressable onPress={onPress} accessibilityRole="button" accessibilityLabel={accessibilityLabel}
      style={({ pressed }) => [pressed && styles.pressed]}>
      {body}
    </Pressable>
  );
}

/**
 * One icon set (Ionicons) on iOS, Android and web. Callers use these short names; the map turns
 * them into Ionicons glyphs.
 */
const ICONS = {
  'chevron.right': 'chevron-forward',
  'chevron.left': 'chevron-back',
  'chevron.down': 'chevron-down',
  business: 'business-outline',
  'arrow.right': 'arrow-forward',
  'checkmark.circle.fill': 'checkmark-circle',
  checkmark: 'checkmark',
  clock: 'time-outline',
  'exclamationmark.triangle.fill': 'alert-circle',
  'doc.text': 'document-text-outline',
  signature: 'create-outline',
  bell: 'notifications-outline',
  'arrow.up.right': 'arrow-up-circle-outline',
  'square.and.arrow.up': 'share-outline',
  'lock.fill': 'lock-closed-outline',
  'wifi.slash': 'cloud-offline-outline',
  magnifyingglass: 'search-outline',
  'person.crop.circle': 'person-circle-outline',
  globe: 'globe-outline',
  wallet: 'wallet-outline',
  cash: 'cash-outline',
  trending: 'trending-up-outline',
  open: 'open-outline',
  flash: 'flash',
  home: 'home-outline',
  logout: 'log-out-outline',
} as const satisfies Record<string, keyof typeof Ionicons.glyphMap>;

export type IconName = keyof typeof ICONS;

export function Icon({ name, size = 18, color = 'textSecondary' }: { name: IconName; size?: number; color?: ThemeColor }) {
  const theme = useTheme();
  return <Ionicons name={ICONS[name]} size={size} color={theme[color]} accessibilityElementsHidden importantForAccessibility="no" />;
}

/** The reference's round icon button (back, bell, share…) */
export function IconButton({ name, onPress, label, badge, tone = 'surfaceAlt' }:
  { name: IconName; onPress?: () => void; label: string; badge?: boolean; tone?: 'surfaceAlt' | 'accent' | 'inverse' }) {
  const theme = useTheme();
  const fg: ThemeColor = tone === 'accent' ? 'onAccent' : tone === 'inverse' ? 'onInverse' : 'text';
  return (
    <Pressable onPress={onPress} accessibilityRole="button" accessibilityLabel={label}
      style={({ pressed }) => [styles.iconButton, { backgroundColor: theme[tone], borderColor: theme.hairline }, pressed && styles.pressed]}>
      <Icon name={name} size={20} color={fg} />
      {badge ? <View style={[styles.dot, { backgroundColor: theme.accent, borderColor: theme[tone] }]} /> : null}
    </Pressable>
  );
}

export function Button({ title, onPress, kind = 'primary', loading, disabled, icon, accessibilityHint }:
  { title: string; onPress: () => unknown; kind?: 'primary' | 'secondary' | 'danger' | 'light'; loading?: boolean; disabled?: boolean; icon?: IconName; accessibilityHint?: string }) {
  const theme = useTheme();
  const bg = { primary: theme.accent, secondary: theme.surfaceAlt, danger: theme.dangerSoft, light: theme.inverse }[kind];
  const fg: ThemeColor = ({ primary: 'onAccent', secondary: 'text', danger: 'danger', light: 'onInverse' } as const)[kind];
  const off = disabled || loading;
  return (
    <Pressable
      accessibilityRole="button" accessibilityState={{ disabled: !!off, busy: !!loading }} accessibilityHint={accessibilityHint}
      disabled={off}
      onPress={async () => {
        if (Platform.OS !== 'web') Haptics.selectionAsync().catch(() => {});
        await onPress();
      }}
      style={({ pressed }) => [styles.button, { backgroundColor: bg, opacity: off ? 0.45 : pressed ? 0.85 : 1 }]}>
      {loading ? <ActivityIndicator color={theme[fg]} /> : (
        <View style={styles.row}>
          {icon ? <Icon name={icon} color={fg} /> : null}
          <AppText variant="bodyStrong" color={fg}>{title}</AppText>
        </View>
      )}
    </Pressable>
  );
}

/** Status is never colour alone: icon + label + colour (proposal principle 5) */
const STATUS: Record<string, { color: ThemeColor; soft: ThemeColor; icon: IconName; label?: string }> = {
  Paid: { color: 'success', soft: 'successSoft', icon: 'checkmark.circle.fill' },
  Overpaid: { color: 'success', soft: 'successSoft', icon: 'checkmark.circle.fill' },
  Signed: { color: 'success', soft: 'successSoft', icon: 'checkmark.circle.fill' },
  Verified: { color: 'success', soft: 'successSoft', icon: 'checkmark.circle.fill' },
  Approved: { color: 'success', soft: 'successSoft', icon: 'checkmark.circle.fill' },
  Pending: { color: 'warning', soft: 'warningSoft', icon: 'clock' },
  'To approve': { color: 'warning', soft: 'warningSoft', icon: 'clock' },
  'To complete': { color: 'warning', soft: 'warningSoft', icon: 'clock' },
  Rejected: { color: 'danger', soft: 'dangerSoft', icon: 'exclamationmark.triangle.fill' },
  'To sign': { color: 'warning', soft: 'warningSoft', icon: 'signature' },
  Overdue: { color: 'danger', soft: 'dangerSoft', icon: 'exclamationmark.triangle.fill' },
};

export function StatusPill({ status }: { status: string }) {
  const theme = useTheme();
  const s = STATUS[status] ?? { color: 'textSecondary' as ThemeColor, soft: 'surfaceAlt' as ThemeColor, icon: 'clock' as IconName };
  return (
    <View style={[styles.pill, { backgroundColor: theme[s.soft] }]} accessibilityLabel={`Status: ${status}`}>
      <Icon name={s.icon} size={12} color={s.color} />
      <AppText variant="caption" color={s.color} style={styles.pillText}>{s.label ?? status}</AppText>
    </View>
  );
}

export function ProgressBar({ value, label }: { value: number; label: string }) {
  const theme = useTheme();
  const pct = Math.max(0, Math.min(100, value));
  return (
    <View accessibilityRole="progressbar" accessibilityLabel={label} accessibilityValue={{ min: 0, max: 100, now: Math.round(pct) }}>
      <View style={[styles.track, { backgroundColor: theme.track }]}>
        <View style={[styles.fill, { width: `${pct}%`, backgroundColor: theme.accent }]} />
      </View>
    </View>
  );
}

/** Placeholder shapes while data loads — the screen keeps its layout (proposal principle 7) */
export function Skeleton({ height = 16, width = '100%', style }: { height?: number; width?: number | `${number}%`; style?: StyleProp<ViewStyle> }) {
  const theme = useTheme();
  // Created once per skeleton; state (not a ref) so render never reads a ref
  const [opacity] = useState(() => new Animated.Value(0.5));
  useEffect(() => {
    const loop = Animated.loop(Animated.sequence([
      Animated.timing(opacity, { toValue: 1, duration: 700, useNativeDriver: Platform.OS !== 'web' }),
      Animated.timing(opacity, { toValue: 0.5, duration: 700, useNativeDriver: Platform.OS !== 'web' }),
    ]));
    loop.start();
    return () => loop.stop();
  }, [opacity]);
  return <Animated.View style={[{ height, width, borderRadius: 10, backgroundColor: theme.skeleton, opacity }, style]} />;
}

export function SkeletonCard({ lines = 3 }: { lines?: number }) {
  return (
    <Card>
      <Skeleton height={18} width="60%" />
      {Array.from({ length: lines }).map((_, i) => <Skeleton key={i} height={14} style={{ marginTop: Spacing.three }} />)}
    </Card>
  );
}

export function EmptyState({ icon = 'checkmark.circle.fill', title, message }: { icon?: IconName; title: string; message?: string }) {
  const theme = useTheme();
  return (
    <View style={styles.empty} accessibilityRole="summary">
      <View style={[styles.emptyIcon, { backgroundColor: theme.surface }]}><Icon name={icon} size={28} color="accent" /></View>
      <AppText variant="heading" style={styles.center}>{title}</AppText>
      {message ? <AppText color="textSecondary" style={styles.center}>{message}</AppText> : null}
    </View>
  );
}

/** Plain-language error with Try again — never a raw error code (proposal principle 8) */
export function ErrorState({ message, onRetry }: { message: string; onRetry: () => void }) {
  return (
    <View style={styles.empty}>
      <Icon name="exclamationmark.triangle.fill" size={32} color="warning" />
      <AppText style={styles.center}>{message}</AppText>
      <Button title="Try again" kind="secondary" onPress={onRetry} />
    </View>
  );
}

export function Row({ label, value, strong }: { label: string; value: ReactNode; strong?: boolean }) {
  return (
    <View style={styles.kv}>
      <AppText color="textSecondary">{label}</AppText>
      {typeof value === 'string' ? <AppText variant={strong ? 'bodyStrong' : 'body'} style={styles.tabular}>{value}</AppText> : value}
    </View>
  );
}

export function Divider() {
  const theme = useTheme();
  return <View style={{ height: StyleSheet.hairlineWidth, backgroundColor: theme.border, marginVertical: Spacing.two }} />;
}

/** Pill tabs: the selected one is a white pill, as in the reference */
export function Segmented<T extends string>({ options, value, onChange }: { options: { value: T; label: string }[]; value: T; onChange: (v: T) => void }) {
  const theme = useTheme();
  return (
    <View style={styles.segmented} accessibilityRole="tablist">
      {options.map((o) => {
        const active = o.value === value;
        return (
          <Pressable key={o.value} onPress={() => onChange(o.value)} accessibilityRole="tab" accessibilityState={{ selected: active }}
            style={[styles.segment, { backgroundColor: active ? theme.inverse : theme.surface }]}>
            {/* One line, never broken mid-word: a long label ("Distributions") on a narrow phone or
                with a large system font shrinks to fit its pill instead of wrapping */}
            <AppText variant={active ? 'bodyStrong' : 'body'} color={active ? 'onInverse' : 'textSecondary'}
              numberOfLines={1} adjustsFontSizeToFit minimumFontScale={0.6} maxFontSizeMultiplier={1.2}>{o.label}</AppText>
          </Pressable>
        );
      })}
    </View>
  );
}

/**
 * A hero amount that always fits on one line: long exact figures (₹5,00,00,000) step down a size
 * rather than wrap.
 */
export function HeroAmount({ children }: { children: string }) {
  const size = children.length > 13 ? 34 : children.length > 10 ? 42 : undefined;
  return (
    <AppText variant="hero" numberOfLines={1} adjustsFontSizeToFit
      style={size ? { fontSize: size, lineHeight: size + 6, letterSpacing: -1 } : undefined}>
      {children}
    </AppText>
  );
}

/** A figure tile: big light number over a small label, with an optional round icon (reference "200 KW/H Produced") */
export function StatTile({ value, unit, label, icon, accent }: { value: string; unit?: string; label: string; icon?: IconName; accent?: boolean }) {
  const theme = useTheme();
  return (
    <LinearGradient colors={[theme.cardTop, theme.cardBottom]} start={{ x: 0, y: 0 }} end={{ x: 0.4, y: 1 }}
      style={[styles.tile, { borderColor: theme.hairline }]} accessibilityLabel={`${label}: ${value}${unit ? ` ${unit}` : ''}`}>
      {icon ? (
        <View style={[styles.tileIcon, { backgroundColor: accent ? theme.accent : theme.surfaceAlt }]}>
          <Icon name={icon} size={18} color={accent ? 'onAccent' : 'text'} />
        </View>
      ) : null}
      <View style={styles.tileFigure}>
        <AppText variant="figure" numberOfLines={1} adjustsFontSizeToFit>{value}</AppText>
        {unit ? <AppText variant="caption" color="textSecondary" style={styles.unit}>{unit}</AppText> : null}
      </View>
      <AppText variant="caption" color="textSecondary">{label}</AppText>
    </LinearGradient>
  );
}

export function Pressy(props: PressableProps & { children: ReactNode }) {
  return <Pressable {...props} style={({ pressed }) => [styles.pressy, pressed && styles.pressed]} />;
}

const styles = StyleSheet.create({
  card: { borderRadius: Radius.card, padding: Spacing.three + 6, gap: Spacing.one, borderWidth: StyleSheet.hairlineWidth, overflow: 'hidden' },
  pressed: { opacity: 0.75 },
  pressy: { minHeight: TouchTarget, justifyContent: 'center' },
  row: { flexDirection: 'row', alignItems: 'center', gap: Spacing.two },
  button: { minHeight: TouchTarget + 8, borderRadius: Radius.pill, alignItems: 'center', justifyContent: 'center', paddingHorizontal: Spacing.four },
  iconButton: { width: TouchTarget + 8, height: TouchTarget + 8, borderRadius: Radius.pill, alignItems: 'center', justifyContent: 'center', borderWidth: StyleSheet.hairlineWidth },
  dot: { position: 'absolute', top: 11, right: 12, width: 9, height: 9, borderRadius: 5, borderWidth: 2 },
  pill: { flexDirection: 'row', alignItems: 'center', gap: 4, paddingHorizontal: 10, paddingVertical: 4, borderRadius: Radius.pill, alignSelf: 'flex-start' },
  pillText: { fontFamily: 'Manrope_600SemiBold' },
  track: { height: 6, borderRadius: Radius.pill, overflow: 'hidden' },
  fill: { height: 6, borderRadius: Radius.pill },
  empty: { alignItems: 'center', justifyContent: 'center', gap: Spacing.three, padding: Spacing.five },
  emptyIcon: { width: 64, height: 64, borderRadius: 32, alignItems: 'center', justifyContent: 'center' },
  center: { textAlign: 'center' },
  kv: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', minHeight: 34, gap: Spacing.three },
  tabular: { fontVariant: ['tabular-nums'], textAlign: 'right', flexShrink: 1 },
  segmented: { flexDirection: 'row', gap: Spacing.two },
  segment: { flex: 1, minHeight: TouchTarget + 6, borderRadius: Radius.pill, alignItems: 'center', justifyContent: 'center', paddingHorizontal: Spacing.two },
  tile: { flex: 1, borderRadius: Radius.tile, padding: Spacing.three + 2, gap: 2, minHeight: 148, justifyContent: 'flex-end', borderWidth: StyleSheet.hairlineWidth, overflow: 'hidden' },
  tileIcon: { position: 'absolute', top: Spacing.three, right: Spacing.three, width: 38, height: 38, borderRadius: 19, alignItems: 'center', justifyContent: 'center' },
  tileFigure: { flexDirection: 'row', alignItems: 'baseline', gap: 4 },
  unit: { textTransform: 'uppercase', letterSpacing: 0.8, fontSize: 11 },
});

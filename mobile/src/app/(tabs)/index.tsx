import { Image } from 'expo-image';
import { router } from 'expo-router';
import { Fragment, useState } from 'react';
import { StyleSheet, View } from 'react-native';

import { useHome, useMe, useSwitchPersona } from '@/api/queries';
import type { ClosedCard, EvergreenCard, FundCard, TodoItem } from '@/api/types';
import { Spacing } from '@/constants/theme';
import { formatDate } from '@/format/date';
import { formatMoneyCompact, moneyNumber, moneyParts } from '@/format/money';
import { useTheme } from '@/hooks/use-theme';
import { useFundManager } from '@/lib/fund-manager';
import { openLink } from '@/lib/links';
import { BrandMark } from '@/ui/brand-mark';
import { FundManagerPicker } from '@/ui/fund-manager-picker';
import { Gauge } from '@/ui/gauge';
import {
  AppText, Card, Divider, EmptyState, ErrorState, Icon, IconButton, ProgressBar, Pressy, SkeletonCard, StatTile, StatusPill,
} from '@/ui/primitives';
import { Screen, Section } from '@/ui/screen';

function greeting() {
  const hour = new Date().getHours();
  return hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';
}

/**
 * Home answers "what do I own, and what do I owe?" at a glance (proposal principle 3, US-3).
 * The dial shows how much of the investor's total commitment has been called; the tiles below
 * show called, due and distributed — all the website card's own figures, summed across funds in
 * the same currency. Then the To do list, then one card per fund. Exact amounts are one tap
 * deeper, on the Fund screen.
 *
 * Everything on Home is for ONE fund manager, picked at the top — never every fund manager mixed
 * together (lp-mobile-multi-site design card ③).
 */
export default function HomeScreen() {
  const me = useMe();
  const { fundManagerId, ready } = useFundManager();
  const home = useHome(fundManagerId, ready);
  const refresh = () => Promise.all([home.refetch(), me.refetch()]);
  const cards = home.data?.cards ?? [];

  return (
    <Screen tabs onRefresh={refresh} updatedAt={home.dataUpdatedAt}
      header={<TopBar initials={initials(me.data?.user)} unread={me.data?.unread_notifications ?? 0} />}>
      <View>
        <AppText color="textSecondary">{greeting()}{me.data ? `, ${me.data.user.first_name}` : ''}</AppText>
        <AppText variant="title" accessibilityRole="header">{me.data?.investor_name ?? 'Your portfolio'}</AppText>
        {me.data?.advisor && me.data.personas.length > 1 ? <PersonaSwitcher /> : null}
        <FundManagerPicker />
      </View>

      {home.isPending ? (
        <>
          <SkeletonCard lines={6} />
          <SkeletonCard lines={2} />
        </>
      ) : home.isError ? (
        <ErrorState message={home.error.message} onRetry={() => home.refetch()} />
      ) : cards.length === 0 ? (
        <>
          <TodoCard items={home.data.todo} />
          <EmptyState icon="wallet" title="No investments yet" message="Your funds appear here once your fund manager gives you access." />
        </>
      ) : (
        <>
          <PortfolioHero cards={cards} />
          <TodoCard items={home.data.todo} />
          <Section title="Funds">
            {cards.map((card) => <FundCardView key={card.commitment_id} card={card} />)}
          </Section>
        </>
      )}
    </Screen>
  );
}

function initials(user?: { first_name: string; last_name: string }) {
  return user ? `${user.first_name[0] ?? ''}${user.last_name[0] ?? ''}`.toUpperCase() : '';
}

function TopBar({ initials: letters, unread }: { initials: string; unread: number }) {
  const theme = useTheme();
  return (
    <View style={styles.topBar}>
      <Brand />
      <View style={styles.topActions}>
        <IconButton name="bell" label={unread ? `Alerts, ${unread} unread` : 'Alerts'} badge={unread > 0} onPress={() => router.navigate('/alerts')} />
        <View style={[styles.avatar, { backgroundColor: theme.inverse }]} accessibilityLabel="Profile">
          <AppText variant="bodyStrong" color="onInverse" onPress={() => router.navigate('/profile')}>{letters}</AppText>
        </View>
      </View>
    </View>
  );
}

/**
 * The top bar's branding: the picked fund manager's own logo when it has one, otherwise — or if
 * the image fails to load — the CapHive mark and name.
 */
function Brand() {
  const { fundManagers, fundManagerId } = useFundManager();
  const current = fundManagers.find((f) => f.id === fundManagerId);
  // Remember which logo failed, so switching to another fund manager tries its logo afresh
  const [failedUrl, setFailedUrl] = useState<string | null>(null);
  const logo = current?.logo_url && current.logo_url !== failedUrl ? current.logo_url : null;

  if (logo) {
    return (
      <Image source={{ uri: logo }} style={styles.logo} contentFit="contain" contentPosition="left"
        accessibilityLabel={current?.name} onError={() => setFailedUrl(logo)} />
    );
  }
  return (
    <View style={styles.brand}>
      <BrandMark />
      <AppText variant="bodyStrong">CapHive</AppText>
    </View>
  );
}

/** The dial + tiles: totals across the closed-ended funds in the investor's main currency */
function PortfolioHero({ cards }: { cards: FundCard[] }) {
  const closed = cards.filter((c): c is ClosedCard => c.kind === 'closed');
  if (closed.length === 0) return null;
  const currency = closed[0].currency;
  const same = closed.filter((c) => c.currency === currency);
  const sum = (key: 'committed' | 'called' | 'due' | 'distributed') => same.reduce((t, c) => t + moneyNumber(c[key]), 0);
  const committed = sum('committed');
  const called = sum('called');
  const pct = committed > 0 ? (called / committed) * 100 : 0;
  const calledParts = moneyParts(called, currency);
  const dueParts = moneyParts(sum('due'), currency);
  const distParts = moneyParts(sum('distributed'), currency);

  return (
    <>
      {/* The dial sits straight on the background, as in the reference */}
      <Gauge value={pct} figure={`${Math.round(pct)}%`} caption={`of ${formatMoneyCompact(committed, currency)} called`} />
      <View style={styles.tiles}>
        <StatTile value={calledParts.value} unit={calledParts.unit} label="Called" icon="trending" />
        <StatTile value={dueParts.value} unit={dueParts.unit} label="Due" icon="clock" accent={sum('due') > 0} />
      </View>
      {/* A wide strip, like the reference's "28 days · On": the figure left, an orange round mark right */}
      <Card style={styles.strip}>
        <View style={styles.grow}>
          <View style={styles.figureRow}>
            <AppText variant="figure">{distParts.value}</AppText>
            <AppText variant="caption" color="textSecondary" style={styles.unit}>{distParts.unit}</AppText>
          </View>
          <AppText variant="caption" color="textSecondary">Distributed to you</AppText>
        </View>
        <View style={styles.stripMark}>
          <IconButton name="cash" label="Distributed" tone="accent" />
        </View>
      </Card>
    </>
  );
}

/** What a screen reader says for each To do item */
function todoLabel(item: TodoItem): string {
  if (item.type === 'capital_call') return `${item.title}, ${formatMoneyCompact(item.amount)} due ${formatDate(item.due_date)}`;
  if (item.type === 'approval') return `Approve ${item.title}, due ${formatDate(item.due_date)}`;
  return `Sign ${item.title}`;
}

function TodoCard({ items }: { items: TodoItem[] }) {
  const theme = useTheme();
  if (items.length === 0) {
    return (
      <Card>
        <View style={styles.row}>
          <View style={[styles.round, { backgroundColor: theme.successSoft }]}><Icon name="checkmark" color="success" /></View>
          <AppText variant="bodyStrong">You&apos;re all caught up</AppText>
        </View>
      </Card>
    );
  }
  return (
    <Card>
      <AppText variant="heading">To do · {items.length}</AppText>
      {items.map((item, i) => (
        <Fragment key={`${item.type}-${item.id}`}>
          {i > 0 ? <Divider /> : null}
          <Pressy onPress={() => openLink(item.link)} accessibilityRole="button"
            accessibilityLabel={todoLabel(item)}>
            <View style={styles.todo}>
              <View style={[styles.round, { backgroundColor: theme.accentSoft }]}>
                <Icon name={item.type === 'capital_call' ? 'wallet' : item.type === 'approval' ? 'checkmark.circle.fill' : 'signature'} color="accent" />
              </View>
              <View style={styles.grow}>
                <AppText variant="bodyStrong">{item.title}</AppText>
                <AppText variant="caption" color="textSecondary">
                  {item.type === 'capital_call' ? `${formatMoneyCompact(item.amount)} · due ${formatDate(item.due_date)}`
                    : item.type === 'approval' ? `Your approval is needed · due ${formatDate(item.due_date)}` : 'Waiting for your signature'}
                </AppText>
              </View>
              <StatusPill status={item.type === 'capital_call' ? item.status : item.type === 'approval' ? 'To approve' : 'To sign'} />
            </View>
          </Pressy>
        </Fragment>
      ))}
    </Card>
  );
}

function FundCardView({ card }: { card: FundCard }) {
  const open = () => router.push({ pathname: '/funds/[id]', params: { id: String(card.commitment_id), kind: card.kind, name: card.fund_name } });
  return card.kind === 'evergreen' ? <EvergreenCardView card={card} onPress={open} /> : <ClosedCardView card={card} onPress={open} />;
}

function ClosedCardView({ card, onPress }: { card: ClosedCard; onPress: () => void }) {
  const committed = moneyParts(card.committed);
  return (
    <Card onPress={onPress} accessibilityLabel={`${card.fund_name}. Committed ${formatMoneyCompact(card.committed)}, ${card.called_pct}% called`}>
      <View style={styles.row}>
        <AppText variant="heading" style={styles.grow}>{card.fund_name}</AppText>
        <Icon name="chevron.right" />
      </View>
      <View style={styles.figureRow}>
        <AppText variant="figure">{committed.value}</AppText>
        <AppText variant="caption" color="textSecondary" style={styles.unit}>{committed.unit} · committed</AppText>
      </View>
      <ProgressBar value={card.called_pct} label={`${card.called_pct}% called`} />
      <View style={styles.stats}>
        <Stat label="Called" value={formatMoneyCompact(card.called)} />
        <Stat label="Due" value={formatMoneyCompact(card.due)} />
        <Stat label="Distributed" value={formatMoneyCompact(card.distributed)} />
      </View>
    </Card>
  );
}

function EvergreenCardView({ card, onPress }: { card: EvergreenCard; onPress: () => void }) {
  return (
    <Card onPress={onPress} accessibilityLabel={`${card.fund_name}, evergreen fund`}>
      <View style={styles.row}>
        <AppText variant="heading" style={styles.grow}>{card.fund_name}</AppText>
        <Icon name="chevron.right" />
      </View>
      <AppText variant="figure">{card.value ? formatMoneyCompact(card.value) : 'NAV not yet published'}</AppText>
      <AppText variant="caption" color="textSecondary">Value{card.nav_date ? ` · NAV ${formatDate(card.nav_date)}` : ''}</AppText>
      <View style={styles.stats}>
        <Stat label="Units" value={Number(card.units).toLocaleString('en-IN', { maximumFractionDigits: 4 })} />
        <Stat label="NAV / unit" value={card.nav_per_unit ? formatMoneyCompact(card.nav_per_unit) : '—'} />
        <Stat label="Gain" value={card.gain ? `${formatMoneyCompact(card.gain)}${card.gain_pct != null ? ` (${card.gain_pct.toFixed(1)}%)` : ''}` : '—'} />
      </View>
    </Card>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.stat}>
      <AppText variant="caption" color="textSecondary">{label}</AppText>
      <AppText variant="bodyStrong" style={styles.tabular}>{value}</AppText>
    </View>
  );
}

/** Advisors switch investor here — the same list and action as the website's persona selector (H8) */
function PersonaSwitcher() {
  const me = useMe();
  const switchPersona = useSwitchPersona();
  const others = (me.data?.personas ?? []).filter((p) => p.id !== me.data?.current_persona_id);
  return (
    <View style={styles.personas}>
      {others.map((p) => (
        <Pressy key={p.id} onPress={() => switchPersona.mutate(p.id)} accessibilityRole="button" accessibilityLabel={`Switch to ${p.name}`}>
          <AppText color="accent">Switch to {p.name}</AppText>
        </Pressy>
      ))}
    </View>
  );
}

const styles = StyleSheet.create({
  topBar: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  brand: { flexDirection: 'row', alignItems: 'center', gap: Spacing.two },
  logo: { height: 28, width: 140 },
  mark: { width: 26, height: 26, borderRadius: 13, alignItems: 'center', justifyContent: 'center' },
  topActions: { flexDirection: 'row', gap: Spacing.two, alignItems: 'center' },
  avatar: { width: 48, height: 48, borderRadius: 24, alignItems: 'center', justifyContent: 'center' },
  row: { flexDirection: 'row', alignItems: 'center', gap: Spacing.three },
  grow: { flex: 1, gap: 2 },
  round: { width: 40, height: 40, borderRadius: 20, alignItems: 'center', justifyContent: 'center' },
  todo: { flexDirection: 'row', alignItems: 'center', gap: Spacing.three, paddingVertical: Spacing.one },
  tiles: { flexDirection: 'row', gap: Spacing.three },
  figureRow: { flexDirection: 'row', alignItems: 'baseline', gap: 6, marginTop: Spacing.two },
  strip: { flexDirection: 'row', alignItems: 'center', paddingVertical: Spacing.three },
  stripMark: { marginLeft: Spacing.three },
  unit: { textTransform: 'uppercase', letterSpacing: 0.8, fontSize: 11 },
  stats: { flexDirection: 'row', justifyContent: 'space-between', marginTop: Spacing.three, gap: Spacing.two },
  stat: { flex: 1, gap: 2 },
  tabular: { fontVariant: ['tabular-nums'] },
  personas: { flexDirection: 'row', flexWrap: 'wrap', gap: Spacing.three },
});

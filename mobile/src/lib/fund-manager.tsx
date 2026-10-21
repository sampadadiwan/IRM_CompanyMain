import { useQuery, useQueryClient } from '@tanstack/react-query';
import { createContext, useCallback, useContext, useMemo, type ReactNode } from 'react';

import { useMe } from '@/api/queries';
import type { FundManager } from '@/api/types';
import { useAuth } from '@/auth/session';
import { fundManagerKey, getItem, setItem } from '@/auth/storage';

/**
 * The one fund manager the app shows (openspec/changes/lp-mobile-multi-site, design card ③).
 *
 * The website's LP dashboard dropdown, on the phone: the list is /me's fund_managers (the user's
 * approved investor accesses, sorted by name) and exactly one is always selected — never every
 * fund manager mixed together:
 *   1. the last pick on this phone for this site, while the user still has access to it (MF-H2);
 *   2. otherwise the first in the list (MF-H1, MF-E1).
 * Home, Documents and Alerts all read `fundManagerId`.
 */
type FundManagerContextValue = {
  fundManagers: FundManager[];
  fundManagerId: number | null;
  /** True once the stored pick and /me are loaded — screens wait, so they never fetch twice */
  ready: boolean;
  choose: (id: number) => void;
};

const FundManagerContext = createContext<FundManagerContextValue | null>(null);

export function FundManagerProvider({ children }: { children: ReactNode }) {
  const { site } = useAuth();
  const me = useMe();
  const client = useQueryClient();
  // The pick is remembered per site on the phone: India and US have different fund managers
  const pickKey = ['fundManagerPick', site?.url ?? ''] as const;
  const stored = useQuery({
    queryKey: pickKey,
    staleTime: Infinity,
    queryFn: async () => {
      const raw = site ? await getItem(fundManagerKey(site.url)) : null;
      return raw ? Number(raw) : null;
    },
  });
  const picked = stored.data ?? null;

  const fundManagers = useMemo(() => me.data?.fund_managers ?? [], [me.data]);
  // The pick only while it is still in the list; otherwise the first (the website's default)
  const fundManagerId = fundManagers.some((f) => f.id === picked) ? picked : (fundManagers[0]?.id ?? null);

  const siteUrl = site?.url;
  const choose = useCallback((id: number) => {
    client.setQueryData(['fundManagerPick', siteUrl ?? ''], id);
    if (siteUrl) setItem(fundManagerKey(siteUrl), String(id)).catch(() => {});
  }, [client, siteUrl]);

  const ready = stored.isSuccess && me.isSuccess;
  const value = useMemo(
    () => ({ fundManagers, fundManagerId, ready, choose }),
    [fundManagers, fundManagerId, ready, choose],
  );
  return <FundManagerContext.Provider value={value}>{children}</FundManagerContext.Provider>;
}

export function useFundManager(): FundManagerContextValue {
  const ctx = useContext(FundManagerContext);
  if (!ctx) throw new Error('useFundManager outside FundManagerProvider');
  return ctx;
}

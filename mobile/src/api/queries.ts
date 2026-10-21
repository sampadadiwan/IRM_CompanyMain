import { useInfiniteQuery, useMutation, useQuery, useQueryClient } from '@tanstack/react-query';

import { api } from '@/api/client';
import type {
  Commitment, DistributionPayment, DocumentDetail, DocumentRow, Home, Me, Notification, Page, PushCategory, Remittance,
} from '@/api/types';
import { setDateFormats } from '@/format/date';

/**
 * Every read the app makes. Where the website already has a JSON endpoint the app uses it with
 * the same phone token (calls, distributions, commitment, document, notifications); only Home,
 * the LP document list, /me, the device and the website hand-off are mobile endpoints.
 */
export const keys = {
  me: ['me'] as const,
  home: ['home'] as const,
  commitment: (id: number) => ['commitment', id] as const,
  calls: (id: number) => ['calls', id] as const,
  distributions: (id: number) => ['distributions', id] as const,
  remittance: (id: number) => ['remittance', id] as const,
  distribution: (id: number) => ['distribution', id] as const,
  documents: (filters: object) => ['documents', filters] as const,
  document: (id: number) => ['document', id] as const,
  notifications: ['notifications'] as const,
};

export function useMe() {
  return useQuery({
    queryKey: keys.me,
    queryFn: async () => {
      const me = await api<Me>('/api/mobile/v1/me');
      setDateFormats(me.date_format, me.time_format);
      return me;
    },
  });
}

export function useHome() {
  return useQuery({ queryKey: keys.home, queryFn: () => api<Home>('/api/mobile/v1/home') });
}

export function useCommitment(id: number) {
  return useQuery({ queryKey: keys.commitment(id), queryFn: () => api<Commitment>(`/capital_commitments/${id}.json`) });
}

export function useCalls(commitmentId: number, enabled = true) {
  return useQuery({
    queryKey: keys.calls(commitmentId),
    enabled,
    queryFn: async () => {
      const rows = await api<Remittance[]>(`/capital_remittances.json?capital_commitment_id=${commitmentId}&all=true`);
      // Newest call first
      return [...rows].sort((a, b) => (b.due_date ?? '').localeCompare(a.due_date ?? ''));
    },
  });
}

export function useDistributions(commitmentId: number, enabled = true) {
  return useQuery({
    queryKey: keys.distributions(commitmentId),
    enabled,
    queryFn: () => api<DistributionPayment[]>(`/capital_distribution_payments.json?capital_commitment_id=${commitmentId}&per_page=100`),
  });
}

export function useRemittance(id: number) {
  return useQuery({ queryKey: keys.remittance(id), queryFn: () => api<Remittance>(`/capital_remittances/${id}.json`) });
}

export function useDistribution(id: number) {
  return useQuery({ queryKey: keys.distribution(id), queryFn: () => api<DistributionPayment>(`/capital_distribution_payments/${id}.json`) });
}

export function useDocuments(filters: { q?: string; commitmentId?: number; toSign?: boolean }) {
  return useInfiniteQuery({
    queryKey: keys.documents(filters),
    initialPageParam: 1,
    getNextPageParam: (last: Page<DocumentRow>) => last.next_page ?? undefined,
    queryFn: ({ pageParam }) => {
      const params = new URLSearchParams({ page: String(pageParam) });
      if (filters.q) params.set('q', filters.q);
      if (filters.commitmentId) params.set('commitment_id', String(filters.commitmentId));
      if (filters.toSign) params.set('to_sign', 'true');
      return api<Page<DocumentRow>>(`/api/mobile/v1/documents?${params}`);
    },
  });
}

export function useDocument(id: number) {
  // Opening it records "viewed by" on the website, as the website's show does (H7)
  return useQuery({ queryKey: keys.document(id), queryFn: () => api<DocumentDetail>(`/documents/${id}.json`) });
}

export function useNotifications() {
  return useQuery({ queryKey: keys.notifications, queryFn: () => api<Notification[]>('/notifications.json?all=1') });
}

export function useMarkRead() {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (id: number) => api(`/notifications/${id}/mark_as_read.json?mark=read`, { method: 'PATCH' }),
    // Optimistic: the dot disappears at once (proposal principle 7)
    onMutate: async (id) => {
      await client.cancelQueries({ queryKey: keys.notifications });
      client.setQueryData<Notification[]>(keys.notifications, (rows) =>
        rows?.map((n) => (n.id === id ? { ...n, read_at: new Date().toISOString() } : n)));
    },
    onSettled: () => client.invalidateQueries({ queryKey: keys.me }),
  });
}

export function useMarkAllRead(userId?: number) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: () => api(`/notifications.json?mark_as_read=1&user_id=${userId}`),
    onSettled: () => {
      client.invalidateQueries({ queryKey: keys.notifications });
      client.invalidateQueries({ queryKey: keys.me });
    },
  });
}

export function useUpdatePushPreferences() {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (changes: Partial<Record<PushCategory, boolean>>) =>
      api<Me>('/api/mobile/v1/me/push_preferences', { method: 'PATCH', body: { push_preferences: changes } }),
    onSuccess: (me) => client.setQueryData(keys.me, me),
  });
}

export function useSwitchPersona() {
  const client = useQueryClient();
  return useMutation({
    // The website's own persona switch (investor_advisors#switch); it answers with a redirect
    mutationFn: (investorAdvisorId: number) => api(`/investor_advisors/switch?id=${investorAdvisorId}`, { method: 'POST' }).catch(() => undefined),
    onSuccess: () => client.invalidateQueries(),
  });
}

export async function updateDevice(attrs: { push_token?: string; push_enabled?: boolean; app_version?: string }) {
  return api<{ push_enabled: boolean; push_status: string }>('/api/mobile/v1/device', { method: 'PUT', body: attrs });
}

/** A one-time link that opens a website page signed in (design card ⑦) */
export async function webHandoffUrl(path: string): Promise<string> {
  const { url } = await api<{ url: string }>('/api/mobile/v1/web_handoffs', { method: 'POST', body: { path } });
  return url;
}

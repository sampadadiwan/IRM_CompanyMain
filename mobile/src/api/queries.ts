import { useInfiniteQuery, useMutation, useQuery, useQueryClient } from '@tanstack/react-query';

import { api } from '@/api/client';
import type {
  ApprovalResponse, Commitment, DistributionPayment, FundRatio, Kyc, RemittancePayment, FundUnit, Holding, DocumentDetail, DocumentRow, Home, Me, Notification, Page, PushCategory, Remittance,
} from '@/api/types';
import { setDateFormats } from '@/format/date';

/**
 * Every read the app makes. Where the website already has a JSON endpoint the app uses it with
 * the same phone token (calls, distributions, commitment, document, notifications); only Home,
 * the LP document list, /me, the device and the website hand-off are mobile endpoints.
 */
export const keys = {
  me: ['me'] as const,
  home: (fundManagerId: number | null) => ['home', fundManagerId] as const,
  commitment: (id: number) => ['commitment', id] as const,
  calls: (id: number) => ['calls', id] as const,
  distributions: (id: number) => ['distributions', id] as const,
  remittance: (id: number) => ['remittance', id] as const,
  distribution: (id: number) => ['distribution', id] as const,
  ratios: (fundId: number, headline: boolean) => ['ratios', fundId, headline] as const,
  units: (commitmentId: number) => ['units', commitmentId] as const,
  portfolio: (fundId: number) => ['portfolio', fundId] as const,
  folioRatios: (commitmentId: number) => ['folioRatios', commitmentId] as const,
  payments: (remittanceId: number) => ['payments', remittanceId] as const,
  approval: (id: number) => ['approval', id] as const,
  kycs: ['kycs'] as const,
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

/** Home for ONE fund manager — the app never mixes fund managers (lp-mobile-multi-site MF-H1) */
export function useHome(fundManagerId: number | null, enabled = true) {
  return useQuery({
    queryKey: keys.home(fundManagerId),
    enabled,
    queryFn: () => api<Home>(`/api/mobile/v1/home${fundManagerId ? `?fund_manager_id=${fundManagerId}` : ''}`),
  });
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

// The LP fund page's Ratios: the fund's own (owner Fund, no folio), Default scenario, latest value of each.
// headline=true gives just the headline ones the website shows on top (FundRatio.headline_ratios).
export function useRatios(fundId: number | undefined, headline: boolean, enabled = true) {
  return useQuery({
    queryKey: keys.ratios(fundId ?? 0, headline),
    enabled: enabled && fundId != null,
    queryFn: () => {
      const params = new URLSearchParams({
        fund_id: String(fundId), fund_ratios_only: 'true', owner_type: 'Fund', scenario: 'Default', latest: 'true', all: 'true',
      });
      if (headline) params.set('headline', 'true');
      return api<FundRatio[]>(`/fund_ratios.json?${params}`);
    },
  });
}

// This folio's own ratios (IRR, MOIC…), latest of each — the server's scope returns only the LP's folios
export function useFolioRatios(commitmentId: number | undefined) {
  return useQuery({
    queryKey: keys.folioRatios(commitmentId ?? 0),
    enabled: commitmentId != null,
    queryFn: () => api<FundRatio[]>(`/fund_ratios.json?capital_commitment_id=${commitmentId}&scenario=Default&latest=true&all=true`),
  });
}

// What the fund has received against one capital call, newest first
export function useRemittancePayments(remittanceId: number) {
  return useQuery({
    queryKey: keys.payments(remittanceId),
    queryFn: async () => {
      const rows = await api<RemittancePayment[]>(`/capital_remittance_payments.json?q[capital_remittance_id_eq]=${remittanceId}&all=true`);
      return [...rows].sort((a, b) => (b.payment_date ?? '').localeCompare(a.payment_date ?? ''));
    },
  });
}

export function useApproval(id: number) {
  return useQuery({ queryKey: keys.approval(id), queryFn: () => api<ApprovalResponse>(`/approval_responses/${id}.json`) });
}

// Answers an approval through the website's own action (approval_responses#approve), then refreshes
// the screen and Home's To do, where the item drops off
export function useRespondToApproval(id: number) {
  const client = useQueryClient();
  return useMutation({
    mutationFn: (status: string) => api(`/approval_responses/${id}/approve.json?status=${encodeURIComponent(status)}`, { method: 'PATCH' }),
    onSuccess: () => {
      client.invalidateQueries({ queryKey: keys.approval(id) });
      client.invalidateQueries({ queryKey: ['home'] });
    },
  });
}

// The LP's KYCs (the server's scope); the screen narrows them to the picked fund manager
export function useKycs() {
  return useQuery({ queryKey: keys.kycs, queryFn: () => api<Kyc[]>('/investor_kycs.json?all=true') });
}

// "Updates required": asks the GP to reopen a submitted or verified KYC (investor_kycs#send_notification)
export function useRequestKycUpdates() {
  return useMutation({
    mutationFn: ({ id, message }: { id: number; message: string }) =>
      api(`/investor_kycs/${id}/send_notification.json`, { method: 'PATCH', body: { message } }),
  });
}

// Units allotted to this folio, newest first
export function useUnits(commitmentId: number, enabled = true) {
  return useQuery({
    queryKey: keys.units(commitmentId),
    enabled,
    queryFn: async () => {
      const rows = await api<FundUnit[]>(`/fund_units.json?q[capital_commitment_id_eq]=${commitmentId}&all=true`);
      return [...rows].sort((a, b) => (b.issue_date ?? '').localeCompare(a.issue_date ?? ''));
    },
  });
}

// The fund's holdings the LP may see (whole fund, or only their allocated ones — the server decides)
export function usePortfolio(fundId: number | undefined, enabled = true) {
  return useQuery({
    queryKey: keys.portfolio(fundId ?? 0),
    enabled: enabled && fundId != null,
    queryFn: () => api<Holding[]>(`/aggregate_portfolio_investments.json?fund_id=${fundId}&all=true`),
  });
}

export function useDocuments(filters: { q?: string; commitmentId?: number; toSign?: boolean; fundManagerId?: number | null }, enabled = true) {
  return useInfiniteQuery({
    queryKey: keys.documents(filters),
    enabled,
    initialPageParam: 1,
    getNextPageParam: (last: Page<DocumentRow>) => last.next_page ?? undefined,
    queryFn: ({ pageParam }) => {
      const params = new URLSearchParams({ page: String(pageParam) });
      if (filters.q) params.set('q', filters.q);
      if (filters.commitmentId) params.set('commitment_id', String(filters.commitmentId));
      if (filters.toSign) params.set('to_sign', 'true');
      if (filters.fundManagerId) params.set('fund_manager_id', String(filters.fundManagerId));
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

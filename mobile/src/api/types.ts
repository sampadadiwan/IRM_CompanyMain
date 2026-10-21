import type { Money } from '@/format/money';

/** GET /api/mobile/v1/me */
export type Me = {
  user: { id: number; first_name: string; last_name: string; email: string };
  region: string;
  locale: string;
  date_format: string;
  time_format: string;
  investor_name: string | null;
  advisor: boolean;
  personas: { id: number; name: string }[];
  current_persona_id: number | null;
  push_preferences: Record<PushCategory, boolean>;
  unread_notifications: number;
  device: { id: number; push_enabled: boolean; push_status: 'none' | 'ok' | 'not_registered' };
};

export type PushCategory = 'capital_calls' | 'distributions' | 'documents' | 'other';

/** GET /api/mobile/v1/home */
export type Home = { todo: TodoItem[]; cards: FundCard[] };

export type TodoItem =
  | { type: 'capital_call'; id: number; title: string; fund_name: string; amount: Money; due_date: string; status: string; link: string }
  | { type: 'signature'; id: number; title: string; link: string };

export type ClosedCard = {
  kind: 'closed'; commitment_id: number; fund_id: number; fund_name: string; entity_name: string; folio_id: string;
  currency: string; committed: Money; called: Money; called_pct: number; due: Money; distributed: Money;
};

export type EvergreenCard = {
  kind: 'evergreen'; commitment_id: number; fund_id: number; fund_name: string; entity_name: string; folio_id: string;
  currency: string; units: string; value: Money | null; gain: Money | null; gain_pct: number | null;
  nav_per_unit: Money | null; nav_date: string | null;
};

export type FundCard = ClosedCard | EvergreenCard;

/** The website's own GET /capital_remittances(.json) rows — reused as-is */
export type Remittance = {
  id: number; capital_call_name: string; fund_name: string; fund_currency: string; status: string;
  call_amount: number; other_fee: number; collected_amount: number; due_amount: number;
  due_date: string | null; payment_date: string | null; folio_id: string;
  notice_document_id?: number | null;
};

/** The website's own GET /capital_distribution_payments(.json) rows — the show adds the notice */
export type DistributionPayment = {
  id: number; capital_distribution_title: string; fund_name: string; payment_date: string | null;
  completed: boolean; net_payable: number; gross_payable: number;
  fund_currency?: string; notice_document_id?: number | null;
};

/** The website's own GET /capital_commitments/:id.json */
export type Commitment = {
  id: number; fund_name: string; fund_currency: string; folio_id: string; committed_amount: number;
  call_amount: number; collected_amount: number; distribution_amount: number; due_amount: number;
};

export type DocumentRow = { id: number; name: string; owner_type: string; owner_tag: string | null; created_at: string };
export type Page<T> = { items: T[]; next_page: number | null };

/** The website's own GET /documents/:id.json, plus the app's signing fields */
export type DocumentDetail = {
  id: number; name: string; s3_url: string; created_at: string;
  signature_status: string | null; sign_action: 'digio_url' | 'docusign_email' | null; sign_url: string | null;
};

/** The website's own GET /notifications.json rows, plus link / category / message / sender */
export type Notification = {
  id: number; message: string; sender: string | null; read_at: string | null; created_at: string;
  link: string; category: PushCategory;
};

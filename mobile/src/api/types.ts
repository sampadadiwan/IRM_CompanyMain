import type { Region } from '@/api/config';
import type { Money } from '@/format/money';

/** A fund manager (GP entity) the LP can pick; logo_url is null when it has no logo */
export type FundManager = { id: number; name: string; logo_url: string | null };

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
  /** The fund managers the picker offers, sorted by name (lp-mobile-multi-site design card ③) */
  fund_managers: FundManager[];
  /** The regions this user can switch to; a switch is shown only when there are two or more */
  regions: Region[];
  push_preferences: Record<PushCategory, boolean>;
  unread_notifications: number;
  device: { id: number; push_enabled: boolean; push_status: 'none' | 'ok' | 'not_registered' };
};

export type PushCategory = 'capital_calls' | 'distributions' | 'documents' | 'other';

/** GET /api/mobile/v1/home */
export type Home = { fund_manager_id: number | null; todo: TodoItem[]; cards: FundCard[] };

export type TodoItem =
  | { type: 'capital_call'; id: number; title: string; fund_name: string; amount: Money; due_date: string; status: string; link: string }
  | { type: 'signature'; id: number; title: string; link: string }
  | { type: 'approval'; id: number; title: string; due_date: string; link: string };

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
  id: number; entity_id: number; fund_id: number; fund_name: string; fund_currency: string; folio_id: string; committed_amount: number;
  call_amount: number; collected_amount: number; distribution_amount: number; due_amount: number;
  /** The fund page's optional sections the GP has switched on (website funds/_investor_fund_details) */
  lp_sections?: { units: boolean; ratios: boolean; portfolio: boolean };
  /** The fund whose ratios the LP sees — the master's for a feeder with none of its own */
  ratios_fund_id?: number; ratios_from_master?: boolean;
};

/** The website's own GET /fund_ratios.json rows (fund-level ratios) */
export type FundRatio = {
  id: number; name: string; display_value: string | null; value: number | null; end_date: string | null;
  scenario: string | null; label: string | null; notes: string | null;
};

/** The website's own GET /fund_units.json rows — units allotted to the LP's folio */
export type FundUnit = {
  id: number; unit_type: string | null; quantity: string; reason: string | null; issue_date: string | null;
  price: number; amount: number;
};

/** The website's own GET /aggregate_portfolio_investments.json rows — one holding of the fund */
export type Holding = {
  id: number; portfolio_company_name: string; investment_instrument_name: string | null; fund_currency: string;
  cost_of_remaining: number; fmv: number; unrealized_gain: number; lp_company_path: string | null;
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
  id: number; message: string; sender: string | null; sender_id: number | null; read_at: string | null; created_at: string;
  link: string; category: PushCategory;
};

/** The website's own GET /approval_responses/:id.json, plus what the app's Approval screen needs */
export type ApprovalResponse = {
  id: number; status: string; owner_label: string; needs_form: boolean; responded_at: string | null;
  approval: {
    id: number; title: string; due_date: string | null; agreements_reference: string | null; entity_name: string;
    response_options: string[]; open: boolean;
  };
  documents: { id: number; name: string }[];
};

/** The website's own GET /capital_remittance_payments.json rows — what the fund received against a call */
export type RemittancePayment = {
  id: number; payment_date: string | null; amount: number; currency: string; reference_no: string | null;
  payment_proof_url: string | null;
};

/** The website's own GET /investor_kycs.json rows (the app shows status only, never PAN or bank details) */
export type Kyc = {
  id: number; entity_id: number; full_name: string | null; kyc_type: string; submission_status: string;
  verified: boolean; docs_completed: boolean; can_request_updates: boolean;
};

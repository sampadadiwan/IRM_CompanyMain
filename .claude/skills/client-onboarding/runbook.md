# Entity-setup runbook (DRAFT — to be corrected by ops)

Derived 2026-10-18 from the entity form and four live fund clients on the production copy
(read-only, port 33066): Ambit Arcadia (7442, onboarded 2026-06), Fireside Ventures (5632),
Artha Venture Partners (3103), Pravega Ventures (841). No written runbook existed.

## 0. Done by ops before the agent starts

- Create the entity (name, entity type e.g. "Investment Fund" / "Angel Fund", currency).
- Set the **feature flags** in `/admin/entities` (CapHive-admin managed, see
  `EntityEnabled` `flag :permissions`). The agent may *propose* the list; ops applies it.
- Add the ops user to the entity and issue the token.
- The client's own team (their users and roles) — ops does this manually; not an agent step
  (decided 2026-10-18).

### Feature flags seen on all four clients (proposed default)

documents, deals, funds, inv_opportunities, investors, account_entries, units, fund_portfolios,
kycs, support, approvals, reports, kanban, import_uploads, investor_advisors, form_types

### Optional — ask ops per client

investments, kpis (portfolio KPIs), compliance, sebi_fields (Indian AIFs), ai_chat, user_llm_chat,
doc_llm_validation, data_rooms, whatsapp, captable, secondary_sale.
`ckyc`/`kra` require `entity_setting.fi_code` first (`validate_critical_flags`).

## 1. Entity settings (agent, via `PATCH /entities/:id.json`)

- `sandbox: true`, `sandbox_emails: <ops email>` — always first.
- `individual_kyc_doc_list`, `non_individual_kyc_doc_list` — from the client's KYC sheets
  (example, Pravega: "PAN, CML, FATCA, Blank Cheque, Address proof, Passport" /
  "PAN, CML, Incorporation, Authorised Signatory, Beneficial ownership, Board resolution").
- `kyc_docs_note`, `cc`, `mailbox` — ask ops.

## 2. Funds

- Create the fund with `POST /funds.json` (name, currency, unit types, first close date). The Fund *import* is
  broken until P3 ships (every row fails "wrong number of arguments"). Category e.g. "Category II"; some clients
  have INR + USD.
- `FundUnitSetting` per unit class (Fireside: 35 across 8 funds).
- Fund custom fields are rare (Fireside: 2).

## 3. Custom fields — where the effort really is

| Form | Ambit 7442 | Fireside 5632 |
|---|---|---|
| IndividualKyc | 83 fields | 44–133 (3 form types) |
| NonIndividualKyc | 282 | 28–241 (3 form types) |
| CapitalCommitment | 1 (Calculation) | 7 |
| Investor | 2 | 2 |
| InvestorAccess | 6 | — |

KYC forms dominate. Several form types with the same name are normal for KYC/commitments
(`FormType::MULTIPLE_FORM_TYPES_ALLOWED`) — e.g. one per fund or investor class.

## Unknowns to confirm with ops

- Document folders / templates, approvals, reports setup.
- Whether DealInvestor / DealActivityTemplate imports belong to onboarding (Ambit did them).

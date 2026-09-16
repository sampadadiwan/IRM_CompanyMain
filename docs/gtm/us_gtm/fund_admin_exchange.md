# Fund Administrator Exchange Layer

**Approach:** Enhance — XLSX import/export and API already exist; what's missing is fund-admin-specific format presets, a `FundAdminProfile` configuration model, and pre-defined exchange schemas
**Phase:** P1 — required for US GPs who use a third-party fund administrator

---

## What This Is

Most US private fund GPs ($500M+) use a third-party fund administrator who handles accounting, tax preparation, and investor capital accounts at the GL level. CapHive sits above the GL — it manages investor onboarding, KYC, capital events, documents, and LP communications. The fund admin needs data from CapHive; CapHive needs data from the fund admin.

CapHive already has the exchange mechanisms:
- **XLSX export** — `ReportBuilder` generates XLSX files on demand and on schedule (`caxlsx`); list views support direct export
- **XLSX import** — `ImportUpload` with `rubyXL` handles structured XLSX for capital calls, commitments, remittances, payments, KYCs, investors, and fund documents (ZIP + index)
- **API** — a structured API layer exposes funds, capital calls, commitments, distributions, remittances, documents, portfolio, and more for programmatic access

What is missing is the **fund-admin-specific configuration layer**: saved format presets per admin, a `FundAdminProfile` that holds the column mapping and contact details, pre-defined exchange schemas for each run type, and the audit log of every exchange run.

> **SFTP is not in scope.** Fund admins will use XLSX download/upload or the API.

---

## Who Uses It

| Persona | When | What They Need |
|---------|------|----------------|
| **CFO / Operations** | After every closing, capital call, and distribution | Send investor master data, KYC status, tax form data, and capital event results to the fund admin in their required format |
| **Fund Administrator (client of GP)** | Receiving data from GP | Get clean, structured XLSX or API access in the format their accounting system expects |
| **IR / Operations** | Receiving data from fund admin | Import capital account statements, NAV data, and K-1 files into CapHive for LP portal delivery |
| **COO** | Onboarding a new fund admin relationship | Configure the exchange format once via `FundAdminProfile`; use it for every subsequent export |

---

## Use Cases

### UC-1: Investor Master Data Export After Closing
A new fund closes with 22 investors. The operations team clicks "Export to Fund Admin" on the closing dashboard. CapHive generates an XLSX using the pre-configured "Alter Domus" format preset: legal name, entity type, EIN/TIN (last 4 masked), formation jurisdiction, address, KYC status, tax form type, and bank instruction details. The fund admin imports this directly into their accounting system.

### UC-2: Capital Call Reconciliation Export
After a capital call is completed, the CFO clicks "Export for Fund Admin" on the capital call page. CapHive generates the reconciliation XLSX: per-investor called amount, equalization basis, folio currency, payment received, payment date, and variance — formatted to match the fund admin's import template. The fund admin uses this to post capital accounts and issue investor statements.

### UC-3: K-1 File Import from Fund Administrator
The fund administrator prepares K-1 PDFs for all investors and delivers a ZIP file. The IR team uploads it via the existing `ImportFundDocsService` (ZIP + index.xlsx with Folio No and As Of Date). CapHive matches files to investor records and populates the Tax Center for LP delivery (see `tax_center.md`).

### UC-4: Capital Account Statement Import
The fund administrator generates quarterly capital account statement PDFs for each investor. The IR team uploads them via the existing document import flow, matched to investors by folio. They become available in the investor portal under the "Statements" section.

### UC-5: API Pull by Fund Administrator
A tech-forward fund admin integrates directly with CapHive's API. They pull investor master data, capital call status, commitment details, and distribution records programmatically after each event — no file exchange needed.

### UC-6: Pre-Configured Admin Format
A GP uses Alter Domus as their fund administrator. During onboarding, their CapHive implementation specialist selects "Alter Domus" from the fund admin format library in `FundAdminProfile`. All subsequent XLSX exports automatically use the Alter Domus column mapping without manual configuration.

---

## Current CapHive State

| Capability | Status | Notes |
|------------|--------|-------|
| Report Builder (custom cross-table XLSX exports) | ✅ Exists | Generates XLSX on demand and on schedule (`caxlsx`); supports cross-model queries; no fund-admin-specific presets saved |
| XLSX export from list views | ✅ Exists | Many list views (capital calls, commitments, remittances, investors) support direct XLSX download |
| XLSX import (`ImportUpload`) | ✅ Exists | `rubyXL`-based XLSX import for capital calls, commitments, remittances, payments, KYCs, investors, fund docs (ZIP + index) |
| Document upload and portal delivery | ✅ Exists | Capital account statements can be uploaded and shared with investors |
| Import of capital call amounts from fund admin | ✅ Exists | Capital call "Upload" basis accepts per-investor amounts from XLSX |
| API access (funds, calls, commitments, distributions, documents) | ✅ Exists | Structured API layer with endpoints for all core fund data objects |
| Fund admin format presets | ❌ Missing | No saved column-mapping configuration per fund admin |
| `FundAdminProfile` model (per-fund admin config) | ❌ Missing | No model to hold admin name, contact, format version, and exchange history |
| Exchange run audit log | ❌ Missing | No record of what was exported/imported, when, by whom, and record count |
| Pre-defined exchange schemas per run type | ❌ Missing | No documented, enforced column mapping per exchange type |
| SFTP | Not planned | Out of scope; fund admins use XLSX download/upload or API |

---

## Build Approach: Enhance existing infrastructure

### New Models

**`FundAdminProfile`** (belongs to Fund/Entity)
- `fund_id` FK
- `admin_name` string (e.g. "Alter Domus", "Standish Management", "Ultimus")
- `admin_type` — enum: `alter_domus`, `standish`, `ultimus`, `nav_consulting`, `u_s_bank`, `gen_ii`, `apex`, `custom`
- `primary_contact_name`, `primary_contact_email`
- `export_format_version` string
- `preferred_exchange_method` — enum: `xlsx`, `api` (no SFTP)

**`FundAdminExchangeRun`** (belongs to FundAdminProfile)
- `run_type` — enum: `investor_master`, `capital_call_reconciliation`, `distribution_reconciliation`, `kyc_status`, `tax_form_status`, `closing_data`
- `direction` — enum: `export`, `import`
- `status` — enum: `pending`, `processing`, `complete`, `error`
- `triggered_by` — enum: `manual`, `event` (auto-triggered on closing or capital call approval)
- `record_count` integer
- `file_attachment` (ActiveStorage)
- `errors` jsonb
- `completed_at` timestamp

### Exchange Schemas

Each `run_type` has a defined schema. For pre-built admin types the column mappings are pre-seeded as configuration. XLSX generation uses the existing `caxlsx` infrastructure; no new export library needed.

**Investor Master Export schema:**

| CapHive Field | Column Label | Notes |
|---|---|---|
| `investor.name` | "Investor Legal Name" | |
| `capital_commitment.folio_id` | "Folio ID" | |
| `investor.json_fields["us_investor_type"]` | "Investor Type" | FormCustomField on Investor |
| `investor_kyc.encrypted_tin` | "EIN/TIN" | Decrypted only during generation; last 4 only in standard export |
| `investor_kyc.verification_status` | "KYC Status" | "Approved" / "Pending" / "Exception" |
| `investor_kyc.json_fields["form_type"]` | "Tax Form Type" | "W-9" / "W-8BEN" etc. |
| `investor_kyc.bank_account_number` | "Bank Account (last 4)" | Masked |
| `capital_commitment.committed_amount` | "Committed Amount" | Fund base currency |
| `capital_commitment.fund_close` | "Fund Close" | |

**Capital Call Reconciliation Export schema:**

| CapHive Field | Column Label |
|---|---|
| `capital_remittance.folio_id` | "Folio ID" |
| `investor.name` | "Investor Name" |
| `capital_remittance.due_amount` | "Amount Called" |
| `capital_remittance.collected_amount` | "Amount Received" |
| `capital_remittance.status` | "Payment Status" |
| `capital_remittance_payment.paid_at` | "Payment Date" |
| `capital_remittance.due_amount - collected_amount` | "Variance" |

### Export Trigger Options
1. **Manual:** "Export to Fund Admin" button on Capital Call, Capital Distribution, Closing, and Investor pages — generates XLSX using the fund's `FundAdminProfile` format preset
2. **Event-triggered:** Auto-export when the last `CapitalCommitment.onboarding_completed` in a fund close flips to `true` and on `CapitalCall.approved`

### Import Handling — Build on Existing `ImportUpload`
- K-1 ZIP import → `ImportFundDocsService` (already exists); routes to Tax Center (`tax_center.md`)
- Capital account statement PDFs → manual upload; matched to investors by folio; added to portal Statements folder
- NAV/account entry data → `ImportAccountEntry` (existing import type) feeds `AccountEntry` records for performance calculation
- Capital call amounts from fund admin → existing "Upload" basis on capital call (already handled by `ImportUpload`)

---

## Functional Requirements

1. Pre-built admin format presets mean zero manual column mapping for common fund administrators — selecting an `admin_type` on `FundAdminProfile` auto-populates the column mapping
2. Sensitive fields (TIN/EIN, account numbers) are decrypted only during XLSX generation; the file is served as a download and not stored persistently on the server
3. Every `FundAdminExchangeRun` is logged with user, timestamp, direction, record count, and file hash for audit purposes
4. Export validation errors (missing required fields, data gaps) are surfaced as a reviewable list before the file is generated
5. Import matching uses Folio No as the primary key; EIN/TIN match as a fallback; unmatched rows land in a review queue
6. Fund admins preferring API access use the existing API directly — no additional build required for this path

---

## Integration Points

- `capital_events_us.md` — reconciliation export schemas defined here; "Export for Fund Admin" triggered from capital call / distribution pages
- `tax_center.md` — K-1 ZIP import uses `ImportFundDocsService`; fund admin exchange layer is the delivery channel
- `us_kyc_kyb.md` — KYC status and AML result included in investor master export
- `us_tax_forms.md` — tax form type and FATCA classification included in investor master export
- `bank_instruction_controls.md` — bank account details (masked) included in investor master export
- `closing_room.md` — closing completion triggers auto-export of investor master data to fund admin
- Existing: `ReportBuilder`, `ImportUpload`, `caxlsx`, `rubyXL` — all exchange mechanics build on these

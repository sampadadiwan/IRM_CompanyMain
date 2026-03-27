# Data Model Descriptions & Relationships

## 1. Document
**Table Name:** `documents`
**Purpose:** Centralized, polymorphic storage for all files across the application. Documents can be attached to various entities (e.g., Users, Funds, Investments) and belong to a specific folder.

**Key Fields:**
- `id` (integer): Primary key.
- `name` (string): The filename or title of the document.
- `file_data` (text): Metadata for the file storage (ActiveStorage/Shrine), containing path, size, etc.
- `text` (string): Extracted raw text content of the document.
- `esign_status` (string), `sent_for_esign` (boolean), `signature_enabled` (boolean), `signed_by_accept` (boolean): Workflow state flags for e-signatures.
- `provider_doc_id` (string): The external ID assigned by an e-signature provider (e.g., Docusign).
- `locked` (boolean), `approved` (boolean): Operational state flags.
- `public_visibility` (boolean), `download` (boolean), `printing` (boolean), `orignal` (boolean): Access rights configuration for viewing and interacting.
- `display_on_page` (string): Determines UI placement for the document.
- `tag_list` (string): Comma-separated or array list of tags used for categorization.
- `owner_tag` (string): Categorization tag related to the parent model.

**Relationships:**
- **Polymorphic Owner:** Uses `owner_type` (string) and `owner_id` (integer) to attach to any model (e.g., User, Investment, KpiReport).
- **Belongs to Entity (`entity_id`):** Links to the core multi-tenant entity scope.
- **Belongs to Folder (`folder_id`):** Points to the directory where the document resides.
- **Belongs to User (`user_id`):** The uploader or creator.
- **Belongs to Template (`from_template_id`):** Self-referential link if the document was generated from another document.
- **Action Users:** Tracks the approver (`approved_by_id`) and signer (`signed_by_id`).

---

## 2. Invest (Investment & Investor)

*(Note: Covered both as "invest" could refer to either the transaction or the entity).*

### Investment
**Table Name:** `investments`
**Purpose:** Represents a capital transaction made by an entity into a portfolio company.

**Key Fields:**
- `investment_date` (date): The date the transaction occurred.
- `investment_type` (string): E.g., primary, secondary.
- `amount_cents` (decimal): Total monetary value invested (stored in cents).
- `currency` (string): 3-letter currency code (e.g., USD, INR).
- `price_cents` (decimal): Price per share/instrument.
- `quantity` (decimal): Number of shares/instruments acquired.
- `instrument_name` (string), `instrument_quantity` (decimal): Details about the specific financial vehicle.
- `funding_round` (string): Phase of funding (e.g., Series A, Seed).
- `investor_name` (string): Label of the investing party.

**Relationships:**
- **Belongs to Entity (`entity_id`):** The tenant/fund making the investment.
- **Belongs to Portfolio Company (`portfolio_company_id`):** The startup receiving the investment.

### Investor
**Table Name:** `investors`
**Purpose:** Represents an individual or institution providing capital.

**Key Fields:**
- `investor_name` (string): Legal or display name.
- `primary_email` (string): Primary contact address.
- `category` (string), `sector` (string): Classification dimensions.
- `pan` (string): Tax identification number.
- `is_holdings_entity` (boolean), `is_trust` (boolean): Entity structure definitions.
- `investor_access_count` (integer): Analytics on platform access.

**Relationships:**
- **Belongs to Entity (`entity_id`):** Multi-tenant scope.
- **Belongs to User/Entity (`investor_entity_id`):** Represents the actual user account mapped to this profile.
- **Has Folder (`document_folder_id`):** Points to a directory storing KYC and related documents.

---

## 3. KpiReport
**Table Name:** `kpi_reports`
**Purpose:** A container mapping to a specific reporting period for a portfolio company. It acts as the parent object for individual metrics.

**Key Fields:**
- `period` (string): The frequency of the report (e.g., "Month", "Quarter", "Year").
- `as_of` (date): The effective end date of the reporting period.
- `analysis` (text): Qualitative commentary or overall health assessment for this period.
- `notes` (text): Supporting context or disclaimers.
- `autofill_completed` (boolean): Flag indicating if AI extraction or system population has finished.
- `enable_portco_upload` (boolean): Flag enabling direct data input by the portfolio company.
- `tag_list` (string): E.g., "Actual", "Budget", "Forecast".

**Relationships:**
- **Has Many Kpis:** Logically linked to multiple KPIs via the `kpi_report_id` on the `kpis` table.
- **Belongs to Portfolio Company (`portfolio_company_id`):** The startup this report evaluates.
- **Belongs to Entity (`entity_id`):** Multi-tenant scope.
- **Belongs to User (`user_id`):** The creator of the report.
- **Belongs to Folder (`document_folder_id`):** Folder for supporting evidence (financials, pitch decks).

---

## 4. Kpi
**Table Name:** `kpis`
**Purpose:** Represents an individual Key Performance Indicator metric instance, logged under a KpiReport.

**Key Fields:**
- `name` (string): The title of the metric (e.g., "MRR", "EBITDA", "Cash Burn").
- `value` (decimal): The absolute numerical value.
- `display_value` (string): The formatted text value for UI purposes (e.g., "$10,000", "5%").
- `percentage_change` (decimal): The relative movement compared to the previous period.
- `common_size_value` (decimal): Normalized percentage (e.g., "marketing spend as % of revenue") for cross-comparison.
- `rag_status` (json): "Red-Amber-Green" health indicator object.
- `status` (string): The approval lifecycle state (e.g., "pending", "approved").
- `source` (string): Data origin (e.g., "Manual", "AI Extracted").
- `notes` (string): Specific commentary explaining this individual metric.

**Relationships:**
- **Belongs to KpiReport (`kpi_report_id`):** Links to the parent period container.
- **Belongs to Portfolio Company (`portfolio_company_id`):** Denormalized link to the target startup for faster querying.
- **Belongs to Entity (`entity_id`):** Multi-tenant scope.
- **Belongs to KpiMapping (`investor_kpi_mapping_id`):** Links to standardized templates to enforce metric consistency.
- **Action Users (`approved_by_user_id`):** User who verified the metric value.
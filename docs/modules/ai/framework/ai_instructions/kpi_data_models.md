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
**Purpose:** Represents a captable transaction made into a portfolio company.

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
**Purpose:** Represents a portfolio company, where category=Portfolio Company

**Key Fields:**
- `investor_name` (string): Legal or display name.
- `primary_email` (string): Primary contact address.
- `category` (string), `sector` (string): Classification dimensions.
- `pan` (string): Tax identification number.
- `is_holdings_entity` (boolean), `is_trust` (boolean): Entity structure definitions.
- `investor_access_count` (integer): Analytics on platform access.

**Relationships:**
- **Belongs to Entity (`entity_id`):** Multi-tenant scope.
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
- `status` (string): The approval lifecycle state (e.g., "pending", "approved").
- `source` (string): Data origin (e.g., "Manual", "AI Extracted").
- `notes` (string): Specific commentary explaining this individual metric.

**Relationships:**
- **Belongs to KpiReport (`kpi_report_id`):** Links to the parent period container.
- **Belongs to Portfolio Company (`portfolio_company_id`):** Denormalized link to the target startup for faster querying.
- **Belongs to Entity (`entity_id`):** Multi-tenant scope.
- **Belongs to KpiMapping (`investor_kpi_mapping_id`):** Links to standardized templates to enforce metric consistency.
- **Action Users (`approved_by_user_id`):** User who verified the metric value.

---

## 5. Sample AI Queries for Portfolio Companies

The following queries demonstrate the expected capabilities of an AI system interacting with this data model, specifically focused on **Portfolio Company** operations and reporting. They are categorized by complexity (Simple, Medium, Complex) and type (Retrieve, Analyze, Chart).

### Retrieve Queries

**Simple**
1. What is the latest reported MRR for [Portfolio Company]?
2. List all KPI reports submitted by [Portfolio Company] during the 2023 fiscal year.
3. Show me the "EBITDA" value for [Portfolio Company] from their Q1 report.
4. What is the total capital we have deployed into [Portfolio Company] to date?
5. Which fund or entity within our structure led the Series A for [Portfolio Company]?
6. What was the "Cash Burn" RAG status for [Portfolio Company] in the most recent period?
7. Show me all KPI reports for [Portfolio Company] that have been internally approved this year.

**Medium**
8. Pull the quarterly "Cash Burn" and "MRR" figures for [Portfolio Company] for all of 2023.
9. Breakdown all secondary transactions in [Portfolio Company] by funding round.
10. Identify all holding entities or special purpose vehicles that hold a stake in [Portfolio Company].
11. Show the analyst commentary and qualitative assessment from [Portfolio Company]'s latest report.
12. Which of [Portfolio Company]'s reporting periods have been fully processed via AI extraction?
13. Identify all investment tranches into [Portfolio Company] that were denominated in INR.
14. Which team members have reviewed and approved KPI metrics for [Portfolio Company] in the last two quarters?
15. Which KPI reports for [Portfolio Company] were uploaded directly by their finance team?

**Complex**
16. Provide a comprehensive snapshot of [Portfolio Company] as of [Date], including all KPIs, health indicators (RAG), and qualitative notes.
17. Generate a full capitalization table summary for [Portfolio Company], including share quantities and instrument types by round.
18. Compare KPIs for [Portfolio Company] that were auto-populated by AI against those that required manual correction in the last period.
19. Show a detailed view of all investors in [Portfolio Company], categorized by their institutional type and sector focus.

### Analyze Queries

**Simple**
26. What was the sequential (QoQ) growth rate in MRR for [Portfolio Company] from Q1 to Q2?
27. Calculate the total number of shares our fund holds in [Portfolio Company] across all series.
28. Is the monthly "Cash Burn" for [Portfolio Company] trending up or down based on the last report?
29. What is the split between primary capital and secondary purchases in our total exposure to [Portfolio Company]?
30. How many times has [Portfolio Company] flagged a "Red" RAG status for EBITDA in the current year?

**Medium**
31. Perform a variance analysis: "Actual" vs "Budget" MRR for [Portfolio Company] year-to-date.
32. Highlight all "Red" RAG metrics for [Portfolio Company] in the latest period and include the explanatory notes.
33. What is our average cost per share for [Portfolio Company] across all investment rounds?
34. Synthesize the qualitative performance trends for [Portfolio Company] over the last four reporting cycles.
35. What is [Portfolio Company]'s current "Efficiency Ratio" (marketing spend as a % of revenue)?
36. Identify if [Portfolio Company] has missed its budget targets for three consecutive months.
37. Analyze our deployment pace into [Portfolio Company] (number of rounds and total capital) over the last three years.
38. Compare the growth trajectory: % change in MRR vs % change in EBITDA for [Portfolio Company] over the last 12 months.
39. Which of [Portfolio Company]'s metrics are currently stuck in "pending" status and require analyst review?

**Complex**
40. Based on the latest round's price and our total share count, what is the current implied valuation of our stake in [Portfolio Company]?
41. Provide a holistic health assessment of [Portfolio Company] by correlating RAG statuses, EBITDA trends, and qualitative commentary over the past year.
42. Evaluate the capital efficiency of [Portfolio Company] by analyzing the relationship between new funding inflows and subsequent "Cash Burn" over 24 months.

### Chart Queries

**Simple**
43. Plot the 12-month MRR trend for [Portfolio Company].
44. Show a pie chart of our investment composition in [Portfolio Company] (Primary vs. Secondary).
45. Create a bar chart showing capital invested in [Portfolio Company] per funding round.

**Medium**
46. Visualize "Actual" vs "Forecast" revenue for [Portfolio Company] on a line chart for the current fiscal year.
47. Generate a stacked bar chart showing the quarterly distribution of RAG statuses (Red/Amber/Green) for [Portfolio Company].
48. Overlay "Cash Burn" and "EBITDA" on a line chart to track [Portfolio Company]'s path to profitability over the last 24 months.

**Complex**
49. Create a dual-axis chart for [Portfolio Company] showing total investment amount per round (bars) against MRR growth percentage (line).
50. Plot a scatter graph for [Portfolio Company] correlating marketing spend efficiency (common_size_value) against absolute MRR growth over the last 8 quarters.
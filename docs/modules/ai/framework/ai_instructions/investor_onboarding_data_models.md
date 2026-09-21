# Investor & KYC Data Models

## 1. Investor
**Table Name:** `investors`
**Purpose:** Represents an individual or institution providing capital. It serves as the primary profile for an investor within a specific entity (multi-tenant).

**Key Fields:**
- `investor_name` (string): Legal or display name.
- `primary_email` (string): Primary contact address, used for identifying and linking to a `User` and `Entity`.
- `category` (string): Classification (e.g., "Individual", "Institutional", "Prospective").
- `sector` (string): Industry focus (primarily for Portfolio Companies).
- `pan` (string): Tax identification number (Permanent Account Number).
- `city` (string): Location of the investor.
- `last_interaction_date` (date): Tracks the last engagement with the investor.

**Relationships:**
- **Belongs to Entity (`entity_id`):** The tenant/fund where this investor record exists.
- **Belongs to Investor Entity (`investor_entity_id`):** Links to the core `Entity` representing the investor's own organization or personal profile.
- **Has Many Investor KYCs (`investor_kycs`):** Links to various KYC records (Individual or Non-Individual).
- **Has Many Capital Commitments (`capital_commitments`):** Links to the financial commitments made by the investor.
- **Has Many Investor Accesses (`investor_accesses`):** Manages which users have permission to access this investor's data.

---

## 2. InvestorKyc
**Table Name:** `investor_kycs`
**Purpose:** Stores the Know Your Customer (KYC) details for an investor. It supports both Individual and Non-Individual types and tracks the verification lifecycle.

**Key Fields:**
- `full_name` (string): Legal name of the investing entity/individual for KYC purposes.
- `kyc_type` (enum): `individual` or `non_individual`.
- `PAN` (string): Tax ID used for regulatory verification.
- `address` (text), `corr_address` (text): Permanent and correspondence addresses.
- `verified` (boolean): Flag indicating if the KYC has been reviewed and approved.
- `completed_by_investor` (boolean): Flag indicating if the investor has finished filling out the form.
- `expired` (boolean): Derived state based on `expiry_date`.
- `aml_status` (string): Status of Anti-Money Laundering checks (e.g., "pending", "cleared").
- `onboarding_status` (string): Tracks the agent-led onboarding progress.

**Key Methods for Agents:**
- `send_kyc_form`: Sends or resends the KYC completion link to the investor.
- `generate_aml_report`: Triggers an asynchronous AML screening job.
- `assign_kyc_data`: Auto-populates fields from verified CKYC/KRA data.

**Relationships:**
- **Belongs to Investor (`investor_id`):** The parent investor profile.
- **Has Many KycDatas (`kyc_datas`):** External verification records from providers like CKYC or KRA.
- **Has Many Documents (`documents`):** Supporting files like PAN card, Passport, or Address proof (polymorphic owner).
- **Has Many AML Reports (`aml_reports`):** History of AML screening results.

---

## 3. KycData
**Table Name:** `kyc_datas`
**Purpose:** Holds raw and parsed data fetched from external KYC registries (CKYC - Central KYC, KRA - KYC Registration Agency). Used for cross-verifying investor-provided info.

**Key Fields:**
- `source` (enum): `ckyc` or `kra`.
- `PAN` (string): The PAN used to fetch the data.
- `response` (json): The full payload from the external provider.
- `verified` (boolean): Whether this specific data point was successfully verified against the registry.

**Relationships:**
- **Belongs to InvestorKyc (`investor_kyc_id`):** The KYC record this data supports.

---

## 4. Onboarding Agent (KycOnboardingAgent)
**Purpose:** An automated service that orchestrates the verification pipeline for `InvestorKyc` records.

**Workflow Steps:**
1. **Field Completeness:** Validates that all required fields are filled and do not contain placeholder text (e.g., "N/A").
2. **Document Presence:** Ensures all mandatory documents (based on KYC type) are uploaded.
3. **Document Validity:** Uses AI (LLM) to verify if the uploaded document matches its label (e.g., is the "PAN Card" upload actually a PAN card?).
4. **Consistency Check:** Cross-references document content against form fields.
5. **AML Trigger:** Automatically triggers `GenerateAmlReportJob` once all blocking issues are resolved.
6. **Reminders:** Sends automated notifications to investors if there are pending actions or invalid submissions.

---

## 5. Sample Agent Queries for Onboarding & KYC

### Retrieve Queries
1. Which investors have a KYC status of "completed" but are not yet "verified"?
2. Show me all `IndividualKyc` records where the PAN card document is missing.
3. What is the current `aml_status` for [Investor Name]?
4. List all investors whose KYC is expiring within the next 30 days.
5. Find all `KycData` records for [Investor Name] that were fetched from CKYC.

### Analyze & Action Queries
6. Identify all blocking issues found by the `KycOnboardingAgent` for [Investor Name].
7. Compare the address in `InvestorKyc` for [Investor Name] with the address returned by `KycData` (KRA).
8. Has a KYC reminder been sent to [Investor Name] in the last 7 days?
9. Trigger a new AML report for all verified KYCs that haven't been screened in 6 months.
10. Summarize the "mismatched document" explanations for [Investor Name]'s onboarding.

### Workflow Queries
11. Send a KYC update request to all investors with "expired" status.
12. Check if [Investor Name] has uploaded all required documents for a "Non-Individual" KYC.
13. Why did the `KycOnboardingAgent` skip the AML trigger for [Investor Name]?

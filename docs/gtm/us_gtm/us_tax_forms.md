# US Tax Form Collection (W-9 / W-8 / FATCA)

**Approach:** Enhance existing `FormCustomField` / `FormType` / `InvestorKyc` system — NOT a new module
**Phase:** P0 — required before any US fund can onboard investors

---

## What This Is

US private funds must collect tax documentation from every investor before admitting them to the fund. The required form depends on whether the investor is a US person or foreign person, and if foreign, their entity type and FATCA classification. Forms expire, must be refreshed on status change, and the data they contain (TIN, FATCA classification, withholding status) flows into fund reporting and tax preparation.

**Key finding:** CapHive's existing `FormCustomField` system on `IndividualKyc` / `NonIndividualKyc` already supports all the data collection required for US tax forms — field collection, conditional display, File upload, and required-field validation. The W-9/W-8 feature is largely a **configuration task** (seed the right form types) plus four targeted engineering additions. No new module is needed.

---

## Who Uses It

| Persona | When | What They Need |
|---------|------|----------------|
| **Operations / Compliance** | Investor onboarding | Know which tax form each investor needs; track receipt and validity; flag expired forms |
| **LP (self) via portal** | Completing onboarding | Be guided to the correct form with conditional questions appearing naturally |
| **CFO / Tax Advisor** | Year-end reporting | Export all tax form data for the fund's tax preparer |
| **Fund Administrator** | Annual reporting | Receive structured tax classification data for 1042-S and K-1 preparation |
| **Compliance / Counsel** | Audit or LP due diligence | Confirm all investors have valid, non-expired forms on file |

---

## Use Cases

### UC-1: US Individual — W-9
A US individual LP completes the KYC flow. The system auto-selects the W-9 form type based on `investor.json_fields["us_investor_type"] = "US Individual"` (a FormCustomField on the `Investor` record). Fields presented: legal name, TIN type (Radio: SSN / EIN / ITIN), TIN (TextField, validated; masked and stored encrypted), address certifications (CheckBox). LP uploads a signed W-9 PDF via the File field. Operations team approves the KYC record.

### UC-2: Foreign Entity — W-8BEN-E with FATCA Classification
A Cayman LP completes the KYC flow. System auto-selects the W-8BEN-E form type. Fields presented: entity name, country, FATCA classification (Select). On selecting "FFI with GIIN," a GIIN field appears (conditional). On selecting "Passive NFFE," a UBO certification notice appears. LP uploads the signed W-8BEN-E via the File field.

### UC-3: Conditional GIIN Field
An investor selects FATCA classification = "FFI with GIIN." The GIIN field (`condition_on = fatca_classification`, `condition_criteria = eq`, `condition_params = ffi_with_giin`) appears and becomes required. The field has a pattern validation rule enforcing the GIIN format (`\A[A-Z0-9]{6}\.[0-9]{5}\.[A-Z]{2}\.[0-9]{3}\z`).

### UC-4: W-8 Expiry Alert
A W-8BEN-E was signed in January 2023 and expires December 31, 2025. A background job running nightly finds the form's `form_expires_at` custom field value, sees it is within 60 days, and sends an alert to the operations team with a link to re-request from the LP.

### UC-5: Tax Data Export for Fund Administrator
The CFO exports a structured CSV: investor name, EIN/TIN (masked last 4), form type, FATCA classification, withholding rate, expiry date. The export format matches the fund administrator's import template.

---

## What the Existing FormCustomField System Already Handles

| Requirement | Existing Support | How |
|-------------|-----------------|-----|
| Multiple form types per KYC | ✅ | `MULTIPLE_FORM_TYPES_ALLOWED` includes `IndividualKyc` and `NonIndividualKyc`; multiple form types per entity/KYC are natively supported |
| Jurisdiction tag separation (US vs SEBI vs GIFT) | ✅ | `FormType.tag` field; uniqueness scoped to `(entity_id, name, tag)`; "US" is just another tag |
| Field collection for all form types | ✅ | TextField, Radio, Select, CheckBox, DateField cover all W-9/W-8 fields |
| File upload for signed form document | ✅ | `File` field type with `max_size_mb` and `allowed_extensions` validation rules; stored as a Document linked to the KYC |
| Conditional field display | ✅ | `condition_on`, `condition_criteria` (`eq`, `not_eq`, `contains`), `condition_state = show` |
| Conditional required enforcement | ✅ | `required = true` on a conditional field is only enforced when the condition is met (`required_fields_for` handles this) |
| GIIN format validation | ✅ | `validation_rules["pattern"]` accepts a regex; GIIN format is a well-defined regex |
| Step-based multi-step form (FATCA wizard) | ✅ | Steps 4–9 on KYC form types support a guided multi-step UX |
| Required field validation | ✅ | `check_required_custom_fields` runs on save; File fields validated separately via document check |
| Dynamic step labels | ✅ | `step_labels` on FormType allows naming each step (e.g. "FATCA Classification," "Withholding Details") |

---

## What Still Needs to Be Built

### 1. Form Type Routing Logic (small — ~50 lines)
The system doesn't automatically select the correct form type when a KYC record is created. Today, form type is selected manually or defaulted.

**Build:** Add a `us_tax_form_type_for(investor)` method in the KYC creation flow that reads `investor.json_fields["us_investor_type"]` (a FormCustomField on the `Investor` record) and `investor_kyc.kyc_type`, then selects the matching US-tagged form type:

```ruby
def us_tax_form_type_for(investor, kyc_class)
  us_type = investor.json_fields["us_investor_type"]
  tag = case [us_type, kyc_class]
        when [/US Individual|US Joint|US IRA/, "IndividualKyc"]      then "US_W9"
        when ["Foreign Individual", "IndividualKyc"]                  then "US_W8BEN"
        when [/US LLC|US LP|US Corp|US Foundation/, "NonIndividualKyc"] then "US_W9"
        when ["Foreign Entity", "NonIndividualKyc"]                   then "US_W8BENE"
        # ...
        end
  entity.form_types.find_by(name: kyc_class, tag: tag)
end
```

This runs once when the KYC record is created or when `investor.json_fields["us_investor_type"]` changes.

### 2. Encrypted TIN Storage (medium — new column + before_save hook)

`json_fields` is a plain JSON column — not encrypted. SSN, ITIN, and EIN must be encrypted at rest; they cannot sit in plain JSON.

**Build:** Add a single encrypted column to `InvestorKyc`:
- `encrypted_tin` — encrypted string (Rails `attr_encrypted` or equivalent)
- `tin_field_name` — string (which form field maps to this: "ssn", "ein", "itin", "foreign_tin")

In the KYC `before_save` hook: if the form type is a US tax form type, extract the TIN value from `json_fields[tin_field_name]`, store it in `encrypted_tin`, and **replace** the `json_fields` value with a masked version ("***-**-1234").

This means the TIN is encrypted at rest; the masked version displays in the UI for reference. Decryption is gated behind an explicit permission check.

### 3. FATCA Tree Depth — Flatten to Stay Within 2-Level Limit

The existing condition chain enforces a 2-level maximum. The FATCA classification tree has some paths deeper than 2 levels (e.g. FFI → registered or deemed-compliant → certified or reporting). 

**Solution:** Flatten the FATCA tree into a single comprehensive Select field with all granular options listed directly — Active NFFE, Passive NFFE, Reporting Model 1 FFI, Reporting Model 2 FFI, Certified Deemed-Compliant FFI, Nonreporting IGA FFI, Exempt Beneficial Owner, etc. Each option directly maps to a set of conditional sub-fields at level 1. This avoids needing a 3-level chain and is actually clearer for the LP.

The 2-level limit then works cleanly: Level 1 condition on `fatca_classification`; level 2 condition on a sub-question (e.g. `has_giin`).

### 4. Form Expiry Alert Job (small — background job)

**Build:** Add a `UsaTaxFormExpiryCheckJob` that runs nightly:
- Queries `InvestorKyc` records where form type tag is `US_W8*`
- Reads `json_fields["form_expires_at"]` 
- For forms expiring within 60 days: sends alert email to ops team with link to re-request
- For forms already expired: sets a flag (`json_fields["form_status"] = "expired"`) that the closing room status logic reads

### 5. Closing Room Tax Form Status Signal (small — computed method)

The closing room needs to ask: "Does this investor have a complete, non-expired US tax form?"

**Build:** Add `us_tax_form_status` computed method on `InvestorKyc`:
```ruby
def us_tax_form_status
  return :not_required unless us_tax_form_type?
  return :expired if json_fields["form_status"] == "expired"
  return :pending unless required_file_documents_present? && required_fields_complete?
  :validated
end
```
This is read by the `check_us_tax_form_status` step in `KycOnboardingAgent` (see `closing_room.md`).

---

## Form Type Seeds to Create

Five `FormType` records per entity (on `IndividualKyc` or `NonIndividualKyc`) with `tag = 'US_*'`:

### W-9 (IndividualKyc + NonIndividualKyc, tag: US_W9)

| Field | Type | Condition | Required |
|-------|------|-----------|----------|
| us_person_name | TextField | — | Yes |
| tin_type | Radio (SSN / EIN / ITIN) | — | Yes |
| tin | TextField (masked on save → encrypted_tin) | — | Yes |
| address | TextArea | — | Yes |
| backup_withholding_exempt | CheckBox | — | No |
| certifications_accepted | CheckBox | — | Yes |
| form_signed_at | DateField | — | Yes |
| form_expires_at | DateField (read-only, auto-computed) | — | No |
| signed_form_upload | File (.pdf, max 10MB) | — | Yes |

### W-8BEN (IndividualKyc, tag: US_W8BEN)

| Field | Type | Condition | Required |
|-------|------|-----------|----------|
| foreign_person_name | TextField | — | Yes |
| country_of_citizenship | Select (country list) | — | Yes |
| foreign_tin | TextField | — | No |
| treaty_claim | CheckBox | — | No |
| treaty_country | Select (country list) | treaty_claim eq true | No |
| treaty_article | TextField | treaty_claim eq true | No |
| withholding_rate | Select (0% / 10% / 15% / 30% / Other) | treaty_claim eq true | No |
| form_signed_at | DateField | — | Yes |
| form_expires_at | DateField (read-only) | — | No |
| signed_form_upload | File (.pdf, max 10MB) | — | Yes |

### W-8BEN-E (NonIndividualKyc, tag: US_W8BENE)

| Field | Type | Condition | Required |
|-------|------|-----------|----------|
| entity_name | TextField | — | Yes |
| country_of_incorporation | Select | — | Yes |
| fatca_classification | Select (Active NFFE / Passive NFFE / Reporting Model 1 FFI / Reporting Model 2 FFI / Certified Deemed-Compliant FFI / Exempt Beneficial Owner / Other) | — | Yes |
| giin | TextField (pattern: GIIN regex) | fatca_classification contains FFI | Conditional |
| passive_nffe_ubo_disclosure | CheckBox | fatca_classification eq Passive NFFE | Conditional |
| treaty_claim | CheckBox | — | No |
| treaty_country | Select | treaty_claim eq true | No |
| withholding_rate | Select | treaty_claim eq true | No |
| form_signed_at | DateField | — | Yes |
| form_expires_at | DateField (read-only) | — | No |
| signed_form_upload | File (.pdf, max 10MB) | — | Yes |

### W-8IMY (NonIndividualKyc, tag: US_W8IMY)

| Field | Type | Condition | Required |
|-------|------|-----------|----------|
| entity_name | TextField | — | Yes |
| intermediary_type | Radio (Qualified / Nonqualified / Flow-through) | — | Yes |
| giin | TextField (pattern: GIIN regex) | intermediary_type eq Qualified | Conditional |
| withholding_statement_attached | CheckBox | — | Yes |
| form_signed_at | DateField | — | Yes |
| signed_form_upload | File (.pdf, max 10MB) | — | Yes |
| withholding_statement_upload | File (.pdf, max 10MB) | — | Yes |

### W-8EXP (NonIndividualKyc, tag: US_W8EXP)

| Field | Type | Condition | Required |
|-------|------|-----------|----------|
| entity_name | TextField | — | Yes |
| exempt_status | Radio (Foreign Government / International Organization / Foreign Tax-Exempt Org / Other) | — | Yes |
| form_signed_at | DateField | — | Yes |
| signed_form_upload | File (.pdf, max 10MB) | — | Yes |

---

## What This Approach Does NOT Handle (acknowledged limits)

| Limitation | Impact | Mitigation |
|------------|--------|-----------|
| TIN in plain `json_fields` until encryption hook added | SSN/EIN visible in JSON until P0 build done | Encryption hook is small; must ship with first US form type seed |
| FATCA tree flattened (not a full branching wizard) | LP sees all FATCA classification options at once; less guided than a purpose-built wizard | Accepted trade-off; operational teams can guide LPs; majority of cases are Active NFFE or W-9 |
| No structured withholding rate derivation (GP enters manually) | Operations team sets withholding rate on W-8 review; not auto-computed from treaty table | Acceptable for Phase 1; Phase 2 can add treaty lookup |
| Expiry alert is a job on `form_expires_at` field value | If the field is not filled, no alert fires | Required field on all W-8 form types; validation enforces it |

---

## Revised Build Estimate

| Item | Effort |
|------|--------|
| Seed 5 US form types with all fields and conditions | 2–3 days (configuration, no code) |
| Form type routing logic | 1 day |
| Encrypted TIN column + before_save masking hook | 2 days |
| Expiry alert job | 1 day |
| Closing room tax form status signal | 1 day |
| **Total** | **~1 week** vs. 6–8 weeks for a new module |

---

## Integration Points

- `us_investor_taxonomy.md` — routing reads `investor.json_fields["us_investor_type"]` (FormCustomField on `Investor`) to select the form type
- `closing_room.md` — reads `InvestorKyc.us_tax_form_status` computed method
- `compliance_evidence_binder.md` — KYC record (with tax form fields and uploaded document) included in evidence binder
- `capital_events_us.md` — withholding rate from `json_fields["withholding_rate"]` used in distribution net payable for foreign investors
- `fund_admin_exchange.md` — tax form type, FATCA classification, and expiry date included in investor master export
- Existing: `FormType`, `FormCustomField`, `InvestorKyc`, `IndividualKyc`, `NonIndividualKyc`, `Document` models

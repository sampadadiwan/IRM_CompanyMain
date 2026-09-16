# US Investor Taxonomy

**Approach:** Enhance using existing `FormCustomField` / `FormType` on `InvestorKyc` — NOT new model fields
**Phase:** P0 — required for correct subscription routing and tax form selection

---

## What This Is

US private funds deal with a wide range of investor types, each with distinct legal, tax, and compliance requirements. The current CapHive investor model has an `Individual` / `Non-Individual` KYC split and configurable custom categories, but no US-specific taxonomy. This means the system cannot automatically route W-9 vs. W-8, apply the correct KYC form type, or flag ERISA investors without knowing what type of investor it is in a US legal sense.

**Key finding:** Almost everything in this feature can be handled using the existing `FormCustomField` system. `Investor` includes `WithCustomField`, so US investor type, ERISA flag, and other investor-level fields can live as FormCustomField on the `Investor` record itself — no model column needed. `IndividualKyc` and `NonIndividualKyc` also include `WithCustomField` for KYC-level fields. The original spec proposed three unnecessary new models (`us_investor_type` enum on `Investor`, `JointInvestorHolder`, `IraDetails`). The only genuine model-level requirement is encrypted storage for SSN/EIN/ITIN.

---

## Who Uses It

| Persona | When | What They Need |
|---------|------|----------------|
| **Investor Relations / Operations** | Onboarding a new LP | Select the investor's US legal type so the correct KYC form type and tax form are routed automatically |
| **Fund Counsel** | Reviewing subscription documents | Confirm the investor's legal type matches their subscription agreement representations |
| **Compliance / CFO** | KYC review and ERISA tracking | Know which investors are benefit plan investors for plan asset percentage tracking |
| **LP (self) via portal** | Completing onboarding questionnaire | Be guided through the correct form sequence based on their investor type |

---

## Use Cases

### UC-1: Individual Investor (US Person)
A US HNW individual is categorised as "US Individual." The KYC wizard auto-selects the US Individual form type: SSN (encrypted), date of birth, address, employer, source of wealth, PEP declaration. Tax form routing reads the category and routes to W-9.

### UC-2: Revocable Living Trust
An investor categorised as "US Trust" gets the US Trust form type: trust name, trust type (revocable/irrevocable via Radio), trustee name, trustee email (added to `esign_emails` on commitment for signature routing), trust formation state, EIN (encrypted), formation document File upload. Tax form: W-9.

### UC-3: IRA / Retirement Account
An investor categorised as "US IRA" gets the US IRA form type: custodian name, custodian EIN (encrypted), IRA account number, IRA type (Select: traditional/Roth/SEP/SIMPLE/self-directed), prohibited transaction representations (CheckBox). All as FormCustomField on `IndividualKyc`. Tax form: W-9 under custodian EIN.

### UC-4: Foreign Entity (Cayman Fund-of-Funds)
An investor categorised as "Foreign Entity" gets the Foreign Entity form type: formation jurisdiction, foreign TIN (encrypted), GIIN where applicable (conditional on FATCA FFI classification), authorised signatory, beneficial owners File upload. Tax form: W-8BEN-E.

### UC-5: ERISA Benefit Plan Investor
An investor categorised as "US Pension Plan" or any other US entity type gets a benefit plan investor CheckBox in their KYC form: "Is this investor an employee benefit plan subject to ERISA or Section 4975 of the Internal Revenue Code?" Checking this box feeds into the fund-level ERISA percentage calculation (see `investor_qualification_engine.md`).

### UC-6: Joint Individual Account
An investor categorised as "US Joint" gets the US Joint form type: primary holder name, primary holder SSN (encrypted), joint holder name, joint holder SSN (encrypted), joint holder ownership percentage, relationship between holders. Joint holder email is added to the commitment's `esign_emails` field so both holders receive the subscription agreement for signature.

---

## What the Existing System Already Handles

| Requirement | Existing Support | How |
|-------------|-----------------|-----|
| US investor type taxonomy | ✅ | `Investor` includes `WithCustomField` — `us_investor_type` can be a Select FormCustomField directly on the `Investor` record. Alternatively, use the existing `Investor.category` field (already configurable per entity). Either way: no new model column. |
| ERISA benefit plan flag on Investor record | ✅ | `Investor` includes `WithCustomField` — `is_benefit_plan_investor` can be a CheckBox FormCustomField on `Investor` directly. No boolean column on the model needed. |
| Conditional fields based on investor type | ✅ | `condition_on = 'category'` on `Investor` FormType is explicitly allowed in `condition_on_custom_field` validation. Fields on `Investor` can show/hide based on category. Fields on `InvestorKyc` can condition on `kyc_type`. |
| IRA fields (custodian, account number, IRA type) | ✅ via FormCustomField | TextField for custodian name, account number; Select for IRA type — all on `IndividualKyc` with "US IRA" form type tag |
| Trust fields (trustee name, trust type, formation docs) | ✅ via FormCustomField | TextField, Radio (revocable/irrevocable), File upload — all on `NonIndividualKyc` with "US Trust" form type tag |
| Joint holder fields (name, ownership %) | ✅ via FormCustomField | TextField, NumberField on `IndividualKyc` with "US Joint" form type tag |
| Joint holder e-sign routing | ✅ | `esign_emails` comma-separated field on `CapitalCommitment` already supports multiple signatories |
| ERISA benefit plan investor flag (per investor) | ✅ via FormCustomField | CheckBox field on any US KYC form type |
| US-specific KYC form type templates | ✅ | Seed `FormType` records with `tag = 'US_*'`; pure configuration |
| Multiple form types per KYC type | ✅ | `MULTIPLE_FORM_TYPES_ALLOWED` includes `IndividualKyc` and `NonIndividualKyc` |
| Form type auto-selection based on investor type | ✅ with ~30 lines of code | Routing logic reads `investor.category` and selects the matching US-tagged form type (same pattern as tax form routing in `us_tax_forms.md`) |

---

## What Cannot Be FormCustomField — The One Real Gap

| Requirement | Why FormCustomField Cannot Cover It |
|-------------|-------------------------------------|
| SSN / EIN / ITIN encrypted storage | `json_fields` is a plain JSON column. SSN, EIN, and ITIN are regulated PII that must be encrypted at rest. Custom fields stored in `json_fields` are not encrypted. |

**The solution** (identical to `us_tax_forms.md`): add a single `encrypted_tin` column to `InvestorKyc` with a `before_save` hook. When the form type is a US type, the hook reads the TIN value from `json_fields`, stores it in `encrypted_tin`, and replaces the `json_fields` value with a masked version (e.g. "***-**-1234"). This is one migration and one ~20-line hook — not a new model.

---

## What This Eliminates vs. the Original Spec

| Original Spec Item | Eliminated By |
|-------------------|---------------|
| `us_investor_type` enum on `Investor` model | Use existing `Investor.category` with US-specific category values |
| `JointInvestorHolder` new model | FormCustomField fields (joint_holder_name, joint_holder_ssn_field, joint_holder_ownership_pct) on IndividualKyc; `esign_emails` for e-sign routing |
| `IraDetails` new model | FormCustomField fields (custodian_name, custodian_ein_field, ira_account_number, ira_type) on IndividualKyc |
| `us_person` / `us_entity` booleans on KYC subclasses | Derived from `investor.category` (US categories → us_person; Foreign categories → not us_person) |
| `entity_legal_type` enum on `NonIndividualKyc` | `investor.category` value carries this information |

---

## Build Approach

### Step 1: Seed US Investor Type Fields on `Investor` (configuration only)

Since `Investor` includes `WithCustomField`, create a `FormType` for `Investor` with `tag = 'US'` and add:

| Field | Type | Options |
|-------|------|---------|
| `us_investor_type` | Select | Individual, Joint, Revocable Trust, Irrevocable Trust, LLC, LP, Corporation, Foundation, Endowment, Pension Plan, IRA, Fund of Funds, Family Office, Foreign Individual, Foreign Entity, Sovereign Wealth Fund |
| `is_benefit_plan_investor` | CheckBox | — |
| `us_person` | Radio | US Person / Non-US Person |

These live in `investor.json_fields` — no model column, no migration. The `condition_on = 'us_investor_type'` can then drive conditional fields elsewhere.

Alternatively, extend `investor_categories` in EntitySetting with US-specific values and continue to use the existing `category` field — both approaches work. The FormCustomField approach is preferable because it keeps the `category` field for its existing access-control role.

### Step 2: Seed US KYC Form Type Templates (configuration only)

One `FormType` per investor category on `IndividualKyc` or `NonIndividualKyc`, tagged `US_*`:

| Form Type Tag | KYC Type | Key Fields |
|--------------|----------|-----------|
| `US_INDIVIDUAL` | IndividualKyc | SSN field (masked → encrypted_tin), DOB, address, employer, source of wealth, PEP CheckBox |
| `US_JOINT` | IndividualKyc | Primary holder SSN (masked → encrypted_tin), joint holder name, joint holder SSN (masked → encrypted_tin), joint holder ownership %, relationship Select |
| `US_TRUST` | NonIndividualKyc | Trust name, trust type Radio (revocable/irrevocable), trustee name, trustee email, formation state, EIN (masked → encrypted_tin), formation doc File |
| `US_LLC_LP_CORP` | NonIndividualKyc | Entity name, state of formation, EIN (masked → encrypted_tin), operating agreement File, authorized signatory, beneficial owners >25% TextField |
| `US_FOUNDATION` | NonIndividualKyc | 501(c)(3) status CheckBox, EIN (masked → encrypted_tin), spending policy, investment committee auth File |
| `US_IRA` | IndividualKyc | Custodian name, custodian EIN (masked → encrypted_tin), account number, IRA type Select, prohibited transaction reps CheckBox |
| `US_PENSION_ERISA` | NonIndividualKyc | Plan name, EIN (masked → encrypted_tin), plan type Select, benefit_plan_investor CheckBox, QPAM/VCOC analysis File |
| `FOREIGN_INDIVIDUAL` | IndividualKyc | Country of residence, foreign TIN (masked → encrypted_tin), passport File |
| `FOREIGN_ENTITY` | NonIndividualKyc | Formation jurisdiction, foreign TIN (masked → encrypted_tin), GIIN conditional field, FATCA classification Select, authorised signatory, UBO File |

### Step 3: Form Type Routing Logic (~30 lines)

Same pattern as `us_tax_forms.md` — read `investor.category` on KYC creation to auto-select the matching form type:

```ruby
def us_form_type_for(investor, kyc_class)
  tag = case investor.category
        when "US Individual"         then "US_INDIVIDUAL"
        when "US Joint"              then "US_JOINT"
        when "US Trust"              then "US_TRUST"
        when "US LLC", "US LP", "US Corporation", "US Family Office" then "US_LLC_LP_CORP"
        when "US Foundation", "US Endowment" then "US_FOUNDATION"
        when "US IRA"                then "US_IRA"
        when "US Pension Plan"       then "US_PENSION_ERISA"
        when "Foreign Individual"    then "FOREIGN_INDIVIDUAL"
        when "Foreign Entity", "Sovereign Wealth Fund" then "FOREIGN_ENTITY"
        end
  entity.form_types.find_by(name: kyc_class, tag: tag)
end
```

### Step 4: Encrypted TIN Column (one migration, one hook)

Add `encrypted_tin` column to `InvestorKyc` (identical to the approach in `us_tax_forms.md` — shared column, shared hook). The `before_save` hook is written once and covers both the tax form TIN and the KYC form TIN since they are the same record.

### Step 5: ERISA Fund-Level Percentage (computed method, no new model)

The per-investor ERISA flag is a CheckBox custom field. The fund-level percentage is a query:

```ruby
# On Fund — reads from investor.json_fields since Investor includes WithCustomField
def benefit_plan_investor_percentage
  total = capital_commitments.sum(:committed_amount_cents)
  return 0 if total.zero?

  erisa_total = capital_commitments
    .joins(:investor)
    .where("investors.json_fields->>'is_benefit_plan_investor' = 'true'")
    .sum(:committed_amount_cents)

  (erisa_total.to_f / total * 100).round(2)
end
```

Alert logic lives in a background job that calls this method daily, same as the tax form expiry job.

---

## Functional Requirements

1. US investor category values are seeded per entity; available in the investor category dropdown
2. KYC form type is auto-selected on KYC creation based on `investor.category`; manually overridable
3. TIN fields in US form types are masked to the last 4 digits in `json_fields`; the real value is stored in `encrypted_tin`; access to `encrypted_tin` is gated by explicit permission check
4. Joint investor: both holder emails are added to `CapitalCommitment.esign_emails` so both receive subscription documents for signature
5. Benefit plan investor CheckBox in ERISA form types feeds into the fund-level ERISA percentage calculation via a daily background job with alerts at 20% and 25%
6. `KycOnboardingAgent` routing check reads `investor.category` to determine which US check steps apply (US categories trigger US-specific validation; non-US categories skip them)

---

## Revised Build Estimate

| Item | Effort |
|------|--------|
| Seed US investor category values per entity | 0.5 day (config) |
| Seed 9 US KYC form type templates with all fields | 3 days (config) |
| Form type routing logic | 0.5 day |
| `encrypted_tin` column + before_save hook (shared with `us_tax_forms.md`) | 2 days — likely already done by the time this runs |
| ERISA percentage computed method + alert job | 1 day |
| **Total** | **~5–7 days** vs. weeks for new model hierarchy |

---

## Integration Points

- `us_tax_forms.md` — shares the `encrypted_tin` column and masking hook; same KYC record
- `investor_qualification_engine.md` — reads `investor.category` for eligibility rule routing; reads benefit_plan_investor CheckBox for ERISA tracking
- `us_kyc_kyb.md` — US form type templates define fields that feed into identity and entity verification
- `closing_room.md` / `KycOnboardingAgent` — reads `investor.category` to determine which US check steps to run

# US Fund Legal Structure & Vehicle Type

**Approach:** FormCustomField on `Fund` for classification fields only — all inter-vehicle relationships already exist in the data model
**Phase:** P0 — required before any US fund can be configured correctly

---

## What This Is

US private funds have specific legal structures and vehicle types that drive document requirements, tax treatment, and investor routing. The current CapHive entity model is generic — it has an `entity_type` field (Investment Fund, Angel Fund, etc.) but no concept of US legal structure (Delaware LP, LLC, SPV) or inter-vehicle relationships (feeder into master, parallel fund alongside main fund).

**Key finding:** `Fund` includes `WithCustomField`, so all classification and structure fields (legal structure, vehicle type, formation jurisdiction, fund exemption type, strategy) can live in `fund.json_fields` as FormCustomField — **no model columns or migrations needed at all**.

Inter-vehicle relationships are already fully modelled in the codebase:
- `Fund` has `belongs_to :master_fund, class_name: "Fund"` and `has_many :feeder_funds` — feeder→master is a named, enforced FK association
- `CapitalCommitment` has `belongs_to :feeder_fund, class_name: "Fund"` — the master fund commitment knows which feeder fund it came from, with a validation enforcing consistency
- Parallel funds and SPVs are separate fund entities; they can be grouped under a common parent entity using the existing `Entity.parent_entity` hierarchy

The `related_to_fund_id` column proposed in an earlier version of this spec is **not needed** — the existing `master_fund_id` / `feeder_fund_id` associations already cover the key relationship. The `Entity` model is left unchanged.

---

## Who Uses It

| Persona | When | What They Need |
|---------|------|----------------|
| **COO / Head of Operations** | Fund setup and configuration | Select the correct legal structure for each vehicle so documents and workflows are configured correctly |
| **Fund Counsel** | Closing and document review | Confirm the legal structure matches the subscription agreement and LPA |
| **CFO / Fund Controller** | Reporting and tax prep | Know the legal structure of each vehicle for tax and regulatory reporting |
| **CapHive Implementation Team** | Onboarding a new GP | Configure the multi-vehicle structure correctly on day one |

---

## Use Cases

### UC-1: Delaware LP Fund with GP LLC and Management Company
A PE firm has three entities: the main fund (Delaware LP), the general partner (Delaware LLC), and the management company (Delaware LLC). The fund entity has `legal_structure = "Delaware LP"` and `vehicle_type = "Main Fund"`. GP and management company entities use the existing parent entity hierarchy — no new fields needed on them.

### UC-2: SPV / Co-Investment Vehicle
A GP creates a co-investment SPV (Delaware LLC) alongside the main fund. The SPV entity has its own Fund record with `vehicle_type = "SPV"` and `legal_structure = "Delaware LLC"`. It is grouped with the parent fund via the existing `Entity.parent_entity_id` hierarchy. It has its own investor roster, capital call, and subscription documents.

### UC-3: Parallel Fund for Strategic Investors
A fund has a main Delaware LP and a parallel Delaware LLC for strategic LPs with different fee terms. The parallel fund entity has `vehicle_type = "Parallel Fund"` and is grouped with the main fund via `Entity.parent_entity_id`. Both vehicles can be grouped in the same capital call cycle.

### UC-4: Cayman Feeder into US Master Fund
A Cayman Islands feeder fund (`legal_structure = "Cayman LP"`, `vehicle_type = "Feeder Fund"`) sets `fund.master_fund` to the US master fund using the existing `master_fund_id` association. Different tax form requirements apply: W-8BEN-E from the feeder entity to the master; the feeder's LPs may be foreign entities requiring their own W-8 forms.

---

## Current CapHive State

| Capability | Status | Notes |
|------------|--------|-------|
| Entity type on Fund (Investment Fund, Angel Fund) | ✅ Exists | `entity_type` on `Entity` model; drives feature flags |
| Parent entity / entity hierarchy | ✅ Exists | `parent_entity` field on Entity; management company → fund hierarchy already works |
| `Fund` includes `WithCustomField` | ✅ Exists | `fund.json_fields` available; full FormCustomField machinery supported |
| Feeder → master fund relationship | ✅ Exists | `Fund belongs_to :master_fund` and `has_many :feeder_funds` — named, FK-enforced associations already in the model |
| Feeder fund commitment tracking | ✅ Exists | `CapitalCommitment belongs_to :feeder_fund`; `allowed_feeder_fund` validation enforces consistency; `fund.capital_commitments.where(feeder_fund_id:)` queries work |
| Parallel fund / SPV grouping | ✅ Exists | Separate fund entities grouped under a common parent entity via `Entity.parent_entity` |
| US legal structure classification | ❌ Missing | No `legal_structure` field on Fund; add as FormCustomField in `fund.json_fields` |
| Vehicle type | ❌ Missing | No `vehicle_type` field; add as FormCustomField |
| Formation jurisdiction | ❌ Missing | No jurisdiction field; add as FormCustomField |
| Fund exemption type (3(c)(1), 3(c)(7), Reg D) | ❌ Missing | No exemption classification on Fund; add as FormCustomField |
| Fund strategy | ❌ Missing | No strategy field; add as FormCustomField |
| Vintage year | ❌ Missing | No vintage year; add as FormCustomField |

---

## Build Approach: FormCustomField on `Fund` + one FK column

### Step 1: Seed US Fund Structure FormType (configuration only)

Create a `FormType` for `Fund` with `tag = 'US_STRUCTURE'` and add the following fields:

| Field Name | Type | Options |
|-----------|------|---------|
| `legal_structure` | Select | Delaware LP, Delaware LLC, Cayman LP, Cayman Ltd, BVI Ltd, Other US, Other Foreign |
| `vehicle_type` | Select | Main Fund, Parallel Fund, Feeder Fund, Blocker, SPV, Co-Investment, Master Fund, Fund-of-One, GP Entity, Management Company |
| `formation_jurisdiction` | TextField | (free text: "Delaware", "Cayman Islands", "British Virgin Islands", etc.) |
| `fund_exemption_type` | Select | 3(c)(1), 3(c)(7), Regulation D 506(b), Regulation D 506(c), Other, Not Applicable |
| `strategy` | Select | Private Equity, Venture Capital, Growth Equity, Credit, Real Assets, Hedge Fund, Multi-Strategy, Other |
| `vintage_year` | NumberField | (integer year) |

All stored in `fund.json_fields`. No migration. No model changes on `Entity` or `Fund`.

### Step 2: No FK Column Needed

All inter-vehicle relationships are already modelled:

| Relationship | How It Is Already Expressed |
|---|---|
| Feeder → Master | `Fund.master_fund_id` FK + `belongs_to :master_fund` + `has_many :feeder_funds` |
| Feeder fund commitment in master | `CapitalCommitment.feeder_fund_id` + `belongs_to :feeder_fund` with consistency validation |
| Parallel fund / SPV grouping | `Entity.parent_entity_id` — parallel funds and SPVs share a common parent entity |

No migration is required. When `vehicle_type = "Feeder Fund"` is set as a FormCustomField, the UI can prompt the user to set `fund.master_fund` using the existing association — no new column, no new association.

### What Downstream Code Reads

```ruby
fund.json_fields["legal_structure"]     # => "Delaware LP"
fund.json_fields["vehicle_type"]        # => "Feeder Fund"
fund.json_fields["fund_exemption_type"] # => "3(c)(7)"
fund.master_fund                        # => the master Fund record (existing association)
fund.feeder_funds                       # => all feeders into this master (existing association)
```

---

## Functional Requirements

1. `legal_structure` and `vehicle_type` FormCustomFields are required when `entity_type = Investment Fund` and `fund.json_fields["formation_jurisdiction"]` contains a US state or "Cayman" — enforced via the `required` flag on the FormCustomField
2. `vehicle_type = "Feeder Fund"` requires `fund.master_fund` to be set — validated in a `Fund` model validation using the existing `master_fund_id` association
3. `fund_exemption_type` is read by the Investor Qualification Engine to determine which eligibility rules apply (see `investor_qualification_engine.md`)
4. `legal_structure` and `formation_jurisdiction` are read by the tax form routing logic (see `us_tax_forms.md`) — US-jurisdiction funds expect W-9 from US investors; Cayman-jurisdiction feeder funds trigger W-8 review
5. `vehicle_type` is read by the `KycOnboardingAgent` US closing check to determine which fund vehicles are in scope for a given closing
6. Capital calls on related parallel funds are coordinated via `Entity.parent_entity_id` grouping; feeder fund capital calls coordinate with the master fund via `fund.master_fund` (see `capital_events_us.md`)

---

## Revised Build Estimate

| Item | Effort |
|------|--------|
| Seed `US_STRUCTURE` FormType with 6 fields | 0.5 day (configuration) |
| Fund setup wizard UI step (including master fund selector when `vehicle_type = "Feeder Fund"`) | 1 day |
| Fund list column additions | 0.5 day |
| **Total** | **~2 days** vs. a multi-field migration on the Entity model |

---

## Integration Points

- `investor_qualification_engine.md` — reads `fund.json_fields["fund_exemption_type"]`
- `us_tax_forms.md` — reads `fund.json_fields["legal_structure"]` and `["formation_jurisdiction"]` for W-8 vs. W-9 routing
- `closing_room.md` / `KycOnboardingAgent` — reads `fund.json_fields["vehicle_type"]` to scope US closing checks
- `capital_events_us.md` — reads `fund.master_fund` / `fund.feeder_funds` for feeder-master capital call coordination; reads `Entity.parent_entity_id` for parallel fund grouping
- Existing: `Fund` model (`WithCustomField` already included), `Entity` model (unchanged)

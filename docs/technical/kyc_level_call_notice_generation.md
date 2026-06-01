# KYC-Level Call Notice Generation

## Overview

By default, a call notice document is generated **per folio** (i.e. one document per `CapitalRemittance` record). When a fund is configured with `call_notice_on = "kyc"`, the notice for each folio also carries consolidated fee and amount figures across all folios that share the same `InvestorKyc`.

This is useful when a single investor KYC has multiple folios in the same fund and the notice needs to show both their individual folio amounts and the combined KYC-level totals side-by-side.

In such a case the

**Fund** will have a custom field **call_notice_on** that will have the value **kyc** - so the kyc level context is added in doc gen and

**Other Folios (Capital Commitments)** will have a custom field **skip_doc_gen** set to **Yes** - so only one document is generated at the kyc level

This custom field must be added manually by the business team and the user can then change its value as needed for doc gen

## Notice generation can be triggered for a remittance from the remittance's show page or for all the remittances of a call from the show page of the call

---

## Configuration

The feature is toggled via a fund-level custom field:

```
fund.json_fields["call_notice_on"] = "kyc"    # enables KYC-level context
```

If not set or set to anything other than folio then doc gen will work as usual

This is read in both the capital call controller and the capital remittance controller:

---

## Document Generation Pipeline

For each `CapitalRemittance`, `CapitalRemittanceDocGenerator` runs the following steps:

```
initialize
  └─ generate
       ├─ base_context                            ← always runs
          ├─ call_notice_folio_level_fees_context ← always runs
          └─ call_notice_per_kyc_context          ← only if call_notice_per_kyc: true
```

`FundAsOf` is constructed using the remittance's `remittance_date`, scoping all fund-level queries to that date.

---

## Fee Types in the Call Notice

call notice fees are stored as **audit fields** inside attribute `json_fields`:

| Audit field key           | Stored in column          |
| ------------------------- | ------------------------- |
| `capital_fees_audit`      | `capital_fee_cents`       |
| `other_fees_audit`        | `other_fee_cents`         |
| `investment_amount_audit` | `investment_amount_cents` |

Each audit field is an array of `[name, date, amount_cents]` tuples, read via `remittance.build_fee_structs(audit_key)`.

---

## Context Variables Added to the Template

### Always present: Folio-level fee breakdowns (`call_notice_folio_level_fees_context`)

These are added for **every** document regardless of the `call_notice_per_kyc` flag.

| Context key                              | Description                                                                                        |
| ---------------------------------------- | -------------------------------------------------------------------------------------------------- |
| `remittance_capital_fees_breakdown`      | Capital fees for **this folio only**, with `total_amount_across_folios` set to the call-wide total |
| `remittance_other_fees_breakdown`        | Other fees for this folio only, with call-wide total annotated                                     |
| `remittance_investment_amount_breakdown` | Investment amount breakdown for this folio only, with call-wide total annotated                    |

Each entry in a breakdown is a struct with:

- `name` — fee line item name
- `amount` — consolidated `Money` amount for this fee name within this folio
- `date` — latest date among matching entries
- `total_amount_across_folios` — the same fee name's total across **all folios in the call**

### When `call_notice_per_kyc: true`: KYC-level fee breakdowns are added (`call_notice_per_kyc_context`)

In addition to the folio-level keys above, the following are added:

| Context key                        | Description                                                                                                     |
| ---------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| `call_capital_fees_breakdown`      | Capital fees consolidated across **all folios in the call**                                                     |
| `kyc_capital_fees_breakdown`       | Capital fees consolidated across folios **sharing the same KYC**, each entry annotated with the call-wide total |
| `call_other_fees_breakdown`        | Other fees across all call folios                                                                               |
| `kyc_other_fees_breakdown`         | Other fees across KYC folios, annotated with call-wide totals                                                   |
| `call_investment_amount_breakdown` | Investment amount breakdown across all call folios                                                              |
| `kyc_investment_amount_breakdown`  | Investment amount breakdown across KYC folios, annotated with call-wide totals                                  |
| `kyc_amounts`                      | Aggregated monetary totals across all KYC folios (see below)                                                    |

#### `kyc_amounts` fields

`kyc_amounts` is an `OpenStruct` with the following fields, all as `Money` objects in the fund currency:

| Field                 | Description                                                                         |
| --------------------- | ----------------------------------------------------------------------------------- |
| `capital_remittances` | Decorated collection of all `CapitalRemittance` records for this KYC                |
| `call_amount`         | Sum of `call_amount_cents` across KYC folios                                        |
| `computed_amount`     | Sum of `computed_amount_cents` (system-computed call amount before manual override) |
| `capital_fee_amount`  | Sum of `capital_fee_cents` across KYC folios                                        |
| `other_fee_amount`    | Sum of `other_fee_cents` across KYC folios                                          |
| `investment_amount`   | Sum of `investment_amount_cents` across KYC folios                                  |
| `total_fee_amount`    | `capital_fee_amount + other_fee_amount`                                             |
| `committed_amount`    | Sum of `committed_amount_cents` across KYC folios                                   |

---

## Implementation Notes

1. **`total_amount_across_folios`:** On each breakdown entry, this field is set to the call-wide total for the same fee name, enabling "your KYC share / full call total" comparisons in templates.

2. **`skip_doc_gen?`:** If `capital_commitment.json_fields["skip_doc_gen"] == "yes"`, document generation is aborted before any file I/O.

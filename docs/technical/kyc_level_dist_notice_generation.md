# KYC-Level Distribution Notice Generation

## Overview

By default, a distribution notice document is generated **per folio** (i.e. one document per `CapitalDistributionPayment` record). When a fund is configured with `call_notice_on = "kyc"`, the notice is instead generated at the **KYC level** — meaning the document for each folio also carries consolidated figures across all folios that share the same `InvestorKyc`.

This is useful when a single investor KYC has multiple folios in the same fund and the notice needs to show both their individual folio amounts and the combined KYC-level totals side-by-side.

In such a case the other folio (Capital commitment) will have a custom field skip_call_notice set to `Yes` so only one document is generated at the kyc level

**Fund** will have a custom field **call_notice_on** that will have the value **kyc** - so the kyc level context is added in doc gen and

**Other Folios (Capital Commitments)** will have a custom field **skip_call_notice** set to **Yes** - so only one document is generated at the kyc level

This custom field must be added manually by the business team and the user can then change its value as needed for doc gen

## Notice generation can be triggered for a distribution payment from the payment's show page or for all the distribution payment of a distribution from the show page of the distribution

## Configuration

The feature is toggled via a fund-level custom field:

```
fund.json_fields["call_notice_on"] = "kyc"   # enables KYC-level context
fund.json_fields["call_notice_on"] = "folio"  # (default) folio-only context -  can also be nil
```

This is read in both the capital distribution controller and the distribution payment controller:

---

## Document Generation Pipeline

For each `CapitalDistributionPayment`, `CapitalDistributionPaymentDocGenerator` runs the following steps:

```
initialize
  └─ generate
       ├─ base_context          ← always runs; loads all_payments once
            ├─ dist_notice_per_kyc_context   ← only if dist_notice_per_kyc: true
            └─ dist_notice_folio_level_fees_context  ← always runs
```

---

## What "Fees" Mean Here

Despite the naming, _fees_ in this context refer to **account entries** bucketed into one of five types defined in `CapitalDistributionFees::DISTRIBUTION_FEE_TYPES`:

| Fee Type            | Effect on payment amounts                           |
| ------------------- | --------------------------------------------------- |
| `Income`            | Added to `income_with_fees_cents`                   |
| `FV For Redemption` | Added to `cost_of_investment_with_fees_cents`       |
| `Reinvestment`      | Added to `reinvestment_with_fees_cents`             |
| `Tax`               | Subtracted from `income_with_fees_cents` (net only) |
| `Expense`           | Subtracted from `income_with_fees_cents` (net only) |

Each `CapitalDistributionPayment` stores its computed account entry audit trail in `json_fields["ae_audit"]` as an array of `[name, date, amount_cents, fee_type]` tuples.

---

## Context Variables Added to the Template

### Always present: Folio-level fee breakdowns (`dist_notice_folio_level_fees_context`)

These are added for **every** document regardless of the `dist_notice_per_kyc` flag.

| Context key                              | Description                                                                    |
| ---------------------------------------- | ------------------------------------------------------------------------------ |
| `dist_fvr_breakdown`                     | FV For Redemption fees consolidated across **all** folios in this distribution |
| `dist_income_breakdown`                  | Income fees across all folios                                                  |
| `dist_expense_breakdown`                 | Expense fees across all folios                                                 |
| `dist_tax_breakdown`                     | Tax fees across all folios                                                     |
| `dist_reinvestment_breakdown`            | Reinvestment fees across all folios                                            |
| `current_payment_fvr_breakdown`          | FV For Redemption fees for **this folio only**                                 |
| `current_payment_income_breakdown`       | Income fees for this folio only                                                |
| `current_payment_expense_breakdown`      | Expense fees for this folio only                                               |
| `current_payment_tax_breakdown`          | Tax fees for this folio only                                                   |
| `current_payment_reinvestment_breakdown` | Reinvestment fees for this folio only                                          |

Each breakdown entry is a struct with:

- `name` — account entry / distribution fee name
- `amount` — consolidated `Money` amount for this fee name
- `date` — latest date among matching entries
- `total_amount_across_folios` — the corresponding fund-wide total for the same fee name (from `dist_*_breakdown`)

### When `dist_notice_per_kyc: true`: KYC-level fee breakdowns (`dist_notice_per_kyc_context`)

In addition to the folio-level keys above, the following are added:

| Context key                  | Description                                                                         |
| ---------------------------- | ----------------------------------------------------------------------------------- |
| `kyc_fvr_breakdown`          | FV For Redemption fees consolidated across all folios **belonging to the same KYC** |
| `kyc_income_breakdown`       | Income fees across KYC folios                                                       |
| `kyc_expense_breakdown`      | Expense fees across KYC folios                                                      |
| `kyc_tax_breakdown`          | Tax fees across KYC folios                                                          |
| `kyc_reinvestment_breakdown` | Reinvestment fees across KYC folios                                                 |
| `kyc_amounts`                | Aggregated monetary totals across all KYC folios (see below)                        |

Each `kyc_*_breakdown` entry also carries `total_amount_across_folios` set to the fund-wide total for the same fee name, so a template can show both the KYC subtotal and the full distribution total in the same row.

#### `kyc_amounts` fields

`kyc_amounts` is a `KycAmounts` struct (typed value object) with the following fields, all as `Money` objects in the fund currency:

| Field                          | Description                                                                  |
| ------------------------------ | ---------------------------------------------------------------------------- |
| `kyc_dist_payments`            | Decorated array of all `CapitalDistributionPayment` records for this KYC     |
| `income`                       | Sum of `income_cents` across KYC folios                                      |
| `cost_of_investment`           | Sum of `cost_of_investment_cents`                                            |
| `net_of_account_entries`       | Sum of `net_of_account_entries_cents` (net AEs after tax/expense deductions) |
| `gross_of_account_entries`     | Sum of `gross_of_account_entries_cents` (gross AEs before deductions)        |
| `net_payable`                  | Sum of `net_payable_cents`                                                   |
| `income_with_fees`             | Sum of `income_with_fees_cents`                                              |
| `cost_of_investment_with_fees` | Sum of `cost_of_investment_with_fees_cents`                                  |
| `reinvestment`                 | Sum of `reinvestment_cents`                                                  |
| `reinvestment_with_fees`       | Sum of `reinvestment_with_fees_cents`                                        |
| `gross_payable`                | Sum of `gross_payable_cents`                                                 |
| `other_fee_amount`             | Sum of `other_fee_cents`                                                     |

> **Note:** `folio_amount` is intentionally excluded from `kyc_amounts` because different folios may use different folio currencies, making a simple sum meaningless.

---

## Key Implementation Notes

1. **Single DB query:** `all_payments` is fetched once with `.includes(:capital_commitment).to_a` in `base_context`. The KYC subset is derived via `Array#select` in Ruby — no second query is issued.

2. **`skip_call_notice?`:** If `capital_commitment.json_fields["skip_call_notice"] == "yes"`, document generation is aborted with a logged message before any file I/O occurs.

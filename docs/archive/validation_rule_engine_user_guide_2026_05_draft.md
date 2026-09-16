# Validation Rule Engine — User Guide

## What Is This Feature?

The Validation Rule Engine checks your data as you fill in forms and before you save. It can flag two types of issues:

| Severity | What It Means | What You Do |
|----------|--------------|-------------|
| **Warning** | Something looks unusual but is allowed | Read the message, then choose to save anyway or go back and fix it |
| **Blocker** | The data violates a hard rule | You must fix the problem before the record can be saved |

Rules fire in two places:

- **As you type / leave a field** — a coloured border appears around the field as early feedback.
- **When you click Save / Generate / Submit** — a modal summarises all issues before anything is written to the database.

---

## Which Forms Are Covered?

| Form | Where To Find It |
|------|-----------------|
| Valuations | Portfolio Company → Valuations → New / Edit |
| Allocation Run | Fund → Allocate Account Entries |
| Fund Ratios | Fund → Generate Fund Ratios |

---

## What the Feedback Looks Like

### Field-level indicators (real-time)

While filling in a form, fields with active rules are highlighted:

- **Yellow border** — a warning rule is firing on this field.
- **Red border** — a blocker rule is firing on this field.

These update automatically as you tab between fields.

### The confirmation modal (on save)

When you click the save/submit button, a modal appears if any rules fired:

**Warnings only** — you can still save.

```
┌─────────────────────────────────────────────┐
│ ⚠  Review Before Saving                     │
├─────────────────────────────────────────────┤
│ │ Valuation date 2026-05-11 is not a        │
│   quarter-end date. Please confirm this is  │
│   intentional.                              │
├─────────────────────────────────────────────┤
│         [Go Back]   [Confirm & Save]        │
└─────────────────────────────────────────────┘
```

Click **Confirm & Save** to proceed, or **Go Back** to revise the form.

**Blockers present** — the save button is hidden; you must fix the issue first.

```
┌─────────────────────────────────────────────┐
│ ✕  Cannot Save — Issues Found               │
├─────────────────────────────────────────────┤
│ │ This allocation run is locked and         │
│   cannot be modified.                       │
├─────────────────────────────────────────────┤
│  Fix the issues above before saving.        │
│                        [Go Back]            │
└─────────────────────────────────────────────┘
```

---

## Default Rules

Some rules are **globally enabled** — they fire for every entity automatically with no setup required. Others are **off by default** and must be explicitly enabled by a Company Admin via a Rule Override. Thresholds can be adjusted by a Company Admin (see the Admin Setup section below).

### Valuation

| Rule | Severity | Default Threshold |
|------|----------|------------------|
| Valuation date is not a quarter-end (Mar 31 / Jun 30 / Sep 30 / Dec 31) | Warning | — |
| Per-share value increased by more than X% vs. the previous valuation for the same instrument | Warning | 50% |
| Per-share value decreased by more than X% vs. the previous valuation for the same instrument | Warning | 50% |

### Allocation Run

| Rule | Severity | Default Threshold |
|------|----------|------------------|
| End date is not a quarter-end | Warning | — |
| The allocation run is locked | Blocker | — |

### Fund Ratios

| Rule | Severity | Default Threshold |
|------|----------|------------------|
| End date is not a quarter-end | Warning | — |
| Fund ratio value is outside the expected range | Warning | 0 – 10 |

---

## Admin Setup

Company Admins can view, enable/disable, and override rules from the Admin area. Changes apply immediately to all users in your entity.

Globally-enabled rules (see Default Rules above) require no setup — they fire automatically. Use the steps below to opt out of a rule, adjust its thresholds, or enable a rule that is off by default.

### Step 1 — Open the Validation Rules list

1. Go to **Admin → Entities** and open your entity.
2. Click the **Validation Rules** button in the entity detail page.
   - This pre-filters the list to your entity's rules and any active global defaults.

Alternatively, go directly to **Admin → Validation Rules**.

### Step 2 — Review the default rules

The list shows all global default rules. Key columns:

| Column | Meaning |
|--------|---------|
| **Name** | Internal identifier |
| **Target Model** | Which form the rule applies to |
| **Severity** | `warning` or `blocker` |
| **Enabled** | Whether the rule is active |
| **Is Default** | `true` = global default, `false` = entity-specific |

### Step 3 — Disable a rule you don't want (opt out)

1. Click **Show** on the rule you want to disable.
2. Open the **Rule Overrides** section at the bottom of the page.
3. Click **New Rule Override**.
4. Set **Enabled** to `false` and save.

The rule is now disabled only for your entity. The global default is untouched.

### Step 3b — Enable a rule that is off by default (opt in)

1. Click **Show** on the rule you want to enable.
2. Open the **Rule Overrides** section and click **New Rule Override**.
3. Set **Enabled** to `true` and save.

The rule will now fire for your entity even though it is globally disabled.

### Step 4 — Change a threshold (e.g. the % change limit)

1. From the rule detail page, click **New Rule Override** in the Rule Overrides section.
2. In **Param Overrides**, enter the new value as JSON:
   ```json
   { "pct_threshold": 25 }
   ```
   This overrides just that parameter; all other rule settings remain as defined globally.
3. Optionally set a custom **Message Override** if you want a different message for your users.
4. Save — the new threshold applies immediately.

### Step 5 — Create a rule specific to your entity

If you need a rule that no other entity should see:

1. Go to **Admin → Validation Rules → New**.
2. Fill in the fields:
   - **Name** — a short identifier, e.g. `valuation_must_have_note`
   - **Target Model** — `Valuation`, `AllocationRun`, or `FundRatio`
   - **Entity** — select your entity (leave blank only for global defaults)
   - **Severity** — `warning` or `blocker`
   - **Condition Tree** — JSON describing when the rule fires (see examples below)
   - **Message Template** — what the user sees (supports `%{field_name}` placeholders)
   - **Enabled** — check this to activate immediately

#### Condition Tree Examples

Check that a date field is a quarter-end:
```json
{
  "op": "AND",
  "conditions": [
    { "field": "valuation_date", "op": "not_quarter_end" }
  ]
}
```

Check that a numeric value is above a threshold stored in params:
```json
{
  "op": "AND",
  "conditions": [
    { "field": "per_share_value_cents", "op": "gt", "param": "min_value" }
  ]
}
```

Combine two conditions with OR:
```json
{
  "op": "OR",
  "conditions": [
    { "field": "value", "op": "lt", "param": "min_value" },
    { "field": "value", "op": "gt", "param": "max_value" }
  ]
}
```

Supported operators: `not_quarter_end`, `eq`, `lt`, `gt`, `blank`, `pct_change_gt`, `pct_change_lt`.

#### Supported Params

Add corresponding values to the **Params** field as JSON:
```json
{ "min_value": 0, "max_value": 10 }
```

### Step 6 — Test your rule

Before relying on a new rule in production:

1. Open the relevant form (e.g. Valuations → New).
2. Enter values that should trigger the rule.
3. Tab out of the field — you should see the coloured border appear.
4. Click Save — the modal should display your rule's message.

If the rule does not fire, check:
- **Enabled** is `true` on the rule (and the override, if any).
- The **Target Model** matches the form you are testing.
- The **Condition Tree** JSON is valid (the admin form will error on invalid JSON).

---

## Frequently Asked Questions

**I confirmed a warning and saved — will I see it again next time I open the record?**
No. The modal only appears during an active save attempt. The rule re-evaluates fresh each time you save.

**Can I override a blocker?**
No. Blockers are enforced server-side and cannot be bypassed with "Confirm & Save". You must resolve the issue before saving.

**A rule is firing incorrectly — what do I do?**
Ask your Company Admin to either disable the rule via a Rule Override or adjust the threshold parameters.

**Does disabling a rule affect other entities?**
No. Each entity's overrides are isolated. Disabling a rule for your entity has no effect on other entities.

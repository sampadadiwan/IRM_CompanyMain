# Custom Field Validations — User Guide

## What Is This Feature?

Custom fields let you capture information specific to your fund or entity — things like PAN numbers, incorporation dates, investor categories, and so on. Previously, the system could enforce that a field was *required* (via the browser form), but it had no way to enforce *what kind of value* was acceptable.

This feature adds two layers of validation to custom fields:

1. **Setup validations** — rules that protect you when *defining* a custom field (e.g., you cannot create a Select field without providing any options).
2. **Data-capture validations** — rules that run when *saving a record* (e.g., a field marked as "must be at least 18" will reject the value 5).

---

## Who Sets Up Validation Rules?

Validation rules are configured by a **company admin** on the Form Type setup page.

Navigation: **Settings → Form Types → [Select a form type] → Edit**

Each custom field in the form has an expandable section (click the caret button on the right of the field row). The bottom part of that expanded section contains the **Validation Rules** inputs.

---

## Part 1 — Setup Validations (When Defining a Custom Field)

These rules fire when an admin saves the Form Type. They prevent misconfigured fields from being created.

### 1a. Field Type Must Be Valid

A custom field's **Field Type** must be one of the recognised types:

`TextField`, `NumberField`, `DateField`, `TextArea`, `CheckBox`, `Radio`, `Select`, `DataList`, `MultiSelect`, `Money`, `File`, `Header`, `GridColumns`, `Calculation`

Any other value is rejected with an error on the Field Type column.

**Why this matters:** Prevents typos or bad imports from creating fields the system cannot render.

---

### 1b. Option-Based Fields Require at Least One Option

Fields of type **Select**, **Radio**, **CheckBox**, **DataList**, or **MultiSelect** require the **Metadata** column to contain at least one option (comma-separated).

| Field Type | Metadata Example |
|---|---|
| Select | `Option A,Option B,Option C` |
| Radio | `Yes,No,Maybe` |
| CheckBox | `Category 1,Category 2` |
| DataList | `India,Singapore,Mauritius` |
| MultiSelect | `Equity,Debt,Convertible` |

**Why this matters:** A Select field with no options renders as an empty dropdown — the user cannot fill it in.

---

### 1c. Regulatory Environment Must Be Recognised

The **Reg Env** field (visible in debug mode) only accepts known regulatory environments:

`SEBI`, `CRISIL`, `IFSC`, `MAS`

Blank is also accepted (most fields are not regulatory).

---

### 1d. Conditional Logic Must Be Consistent

When you use the **Condition On** feature (field B only appears when field A has a certain value):

- `Condition Criteria` must be one of: `eq`, `not_eq`, `contains`, `lt`, `lte`, `gt`, `gte`
- `Condition State` must be `show`
- The field referenced in `Condition On` must already exist in the same form type
- Condition chains cannot go deeper than two levels (field C depends on field B which depends on field A — that is the maximum)

---

### 1e. Validation Rules Must Be Consistent With the Field Type

If you set **Validation Rules** on a field (see Part 2), the system checks that the rules make sense for that field's type. Examples of what gets caught:

- Setting `min_length` on a NumberField (length is only meaningful for text)
- Setting `min_value` on a DateField (use `min_date` instead)
- Setting `min_length` to 10 but `max_length` to 5 (min cannot exceed max)
- Entering an invalid regular expression in `pattern`
- Using an unrecognised value for `format`

---

## Part 2 — Validation Rules (Data Capture)

These rules are configured per custom field and run every time a record is saved. They are **opt-in**: a field with no validation rules set behaves exactly as before.

### How to Set a Validation Rule

1. Go to **Settings → Form Types** and open the relevant form type for editing.
2. Find the custom field you want to add rules to.
3. Click the **caret (▼) button** on the right of that field row to expand it.
4. Scroll to the **Validation Rules** section at the bottom of the expanded row.
5. Fill in the relevant inputs (described below).
6. Click **Save** at the bottom of the form.

---

### Rules Available by Field Type

#### TextField and TextArea

| Rule | What It Does | Example |
|---|---|---|
| **Min Length** | Value must be at least this many characters | `5` — rejects values shorter than 5 chars |
| **Max Length** | Value cannot exceed this many characters | `100` — rejects values longer than 100 chars |
| **Pattern** | Value must match this regular expression | `^[A-Z0-9]{10}$` — exactly 10 uppercase alphanumeric chars |
| **Format Shortcut** | Validates against a named format (see table below) | `pan` — enforces Indian PAN card format |

**Format shortcuts available:**

| Shortcut | Pattern It Enforces | Example Valid Value |
|---|---|---|
| `email` | Standard email address | `investor@example.com` |
| `phone` | 7–20 digit phone number (with spaces, +, -, brackets) | `+91 98765 43210` |
| `url` | URL starting with http:// or https:// | `https://example.com` |
| `alphanumeric` | Letters and digits only, no spaces or symbols | `ABC123` |
| `pan` | Indian PAN card (5 letters, 4 digits, 1 letter) | `ABCDE1234F` |
| `gstin` | Indian GST Identification Number (15 chars) | `27AAPFU0939F1ZV` |
| `ifsc` | Indian bank IFSC code (4 letters, 0, 6 alphanumeric) | `HDFC0001234` |

> **Note:** Use either `Pattern` (your own regex) or `Format Shortcut` — not both. `Format Shortcut` is easier to use; `Pattern` gives you full control.

---

#### NumberField and Money

| Rule | What It Does | Example |
|---|---|---|
| **Min Value** | Value must be at least this number | `0` — rejects negative numbers |
| **Max Value** | Value cannot exceed this number | `100` — useful for percentages |

> **Tip:** For a percentage field, set Min Value = `0` and Max Value = `100`.

---

#### DateField

| Rule | What It Does | Example |
|---|---|---|
| **Min Date** | Date cannot be before this date | `2020-01-01` or `today` |
| **Max Date** | Date cannot be after this date | `2030-12-31` or `today` |

The special value **`today`** is resolved at the time the record is saved — it always means the current date, not the date you set up the rule.

**Common uses:**
- "Date of joining cannot be in the past" → set Min Date to `today`
- "Expiry date cannot be before incorporation date" → set Min Date to a fixed anchor date

---

#### MultiSelect and CheckBox

| Rule | What It Does | Example |
|---|---|---|
| **Min Selections** | At least this many options must be chosen | `1` — at least one checkbox must be ticked |
| **Max Selections** | At most this many options may be chosen | `3` — user can pick up to three values |

---

### Universal Rules (All Field Types)

These apply regardless of field type:

| Rule | What It Does |
|---|---|
| **Unique** | The value must be unique across all records of this model for this entity. E.g., no two investors can have the same GSTIN. |
| **Custom Error Message** | Replaces the default error text with your own message. If blank, the system generates a message automatically. |

---

### What Happens When a Rule Is Violated?

When a user tries to save a record and a validation rule is violated, the record is **not saved**. The error message appears at the top of the form, explaining which field failed and why. For example:

> "PAN must be a valid pan"
> "Age must be at least 18"
> "Join Date cannot be before 2024-01-01"

The user must correct the value before the record can be saved.

---

### Client-Side vs. Server-Side

Validation rules work in two places:

| Where | When It Fires | What It Does |
|---|---|---|
| **Browser (client-side)** | As the user fills in the form | Shows `required`, `min`, `max`, `pattern`, `minlength`, `maxlength` constraints directly on the HTML input |
| **Server (server-side)** | When the form is submitted | Runs the full validation_rules logic — catches any value that bypasses the browser |

Both layers enforce the same rules. The server-side check is the authoritative one — values cannot be saved to the database without passing it.

---

## Part 3 — Examples

### Example 1: PAN Number Field

You want a TextField called "PAN" where:
- The value must follow the PAN format
- It must be unique across all investors

Configuration:
- Field Type: `TextField`
- Format Shortcut: `pan`
- Unique: ✓ checked

Result: `ABCDE1234F` → saved. `ABC123` → rejected. A duplicate PAN → rejected.

---

### Example 2: Age Field for KYC

You want a NumberField called "Age" where:
- The investor must be at least 18
- The investor cannot be older than 120

Configuration:
- Field Type: `NumberField`
- Min Value: `18`
- Max Value: `120`

Result: `25` → saved. `16` → rejected with "Age must be at least 18". `abc` → rejected with "Age must be a number".

---

### Example 3: Commitment Date

You want a DateField called "Commitment Date" where:
- The date cannot be in the future

Configuration:
- Field Type: `DateField`
- Max Date: `today`

Result: Yesterday's date → saved. Tomorrow's date → rejected with "Commitment Date cannot be after [today's date]".

---

### Example 4: Investment Strategy (MultiSelect)

You want a MultiSelect called "Strategy" where:
- At least one strategy must be selected
- No more than three strategies may be selected

Configuration:
- Field Type: `MultiSelect`
- Metadata: `Growth,Value,Distressed,Special Situations,Real Assets`
- Min Selections: `1`
- Max Selections: `3`

Result: Selecting two strategies → saved. Selecting none → rejected. Selecting four → rejected.

---

### Example 5: Custom Error Message

You want a TextField for GSTIN with a helpful, business-friendly error message.

Configuration:
- Field Type: `TextField`
- Format Shortcut: `gstin`
- Custom Error Message: `Please enter a valid 15-character GSTIN (e.g. 27AAPFU0939F1ZV)`

Result: An invalid value shows "Please enter a valid 15-character GSTIN (e.g. 27AAPFU0939F1ZV)" instead of the default "Gstin is not a valid gstin".

---

## Part 4 — Import / Bulk Operations

Custom field validation rules are stored in the `validation_rules` column of each `FormCustomField` record. When importing FormCustomField definitions via spreadsheet, validation rules are **not** part of the import template currently — they must be set through the UI.

Bulk data imports (investor imports, KYC imports, etc.) that use `skip_cf_before_save` will bypass all custom field validations including the new rules. This is intentional for large imports where you want to bring data in first and clean it up later.

---

---

## Appendix — Backward Compatibility Review (For Business Sign-Off)

> **Purpose of this section:** The following changes alter how the system behaves for existing production data. The development team needs a business decision on each point before the feature is enabled in production.

---

### Issue 1 — Required Fields Now Block Saves at the Server Level

**Current behaviour (working):** Marking a custom field as "Required" only enforces the rule in the browser form. Records saved via import, API, or older forms silently accept blank values.

**New behaviour:** The server checks required fields on every save. A record with a blank required custom field **cannot be saved**.

**Potential impact:** Any record in production that was saved without filling a required custom field will fail the next time it is saved — even if the user is updating something unrelated (e.g., changing an investor's email address).

**Action needed before enabling:**
- Run a report to identify all records where a required custom field has a blank value.
- Either fill in the missing values, or temporarily un-mark those fields as required.

---

### Issue 2 — Non-Numeric Values in NumberFields Now Block Saves

**Current behaviour (working):** NumberField and Money fields accept any text value. Strings like `"N/A"`, `"TBD"`, or `"~500"` are stored and saved without error.

**New behaviour:** The server rejects any non-blank value in a NumberField or Money field that is not a valid number.

**Potential impact:** Any record where a NumberField was used to store text (common in data migrated from spreadsheets) will fail on the next save.

**Action needed before enabling:**
- Audit NumberField and Money custom field values for non-numeric content.
- Either clean the data, or convert those fields to TextField if they genuinely hold mixed values.

---

### Issue 3 — Unparseable Dates in DateFields Now Block Saves

**Current behaviour (working):** DateField accepts any text value. Strings like `"Q1 2023"`, `"circa 1998"`, or `"Unknown"` are stored without error.

**New behaviour:** The server rejects any non-blank value in a DateField that cannot be parsed as a valid date.

**Potential impact:** Same as Issue 2 — most common in historically imported data.

**Action needed before enabling:**
- Audit DateField custom field values for unparseable content.
- Either clean the data, or convert those fields to TextField.

---

### Issue 4 — Existing Select/Radio/CheckBox Fields Without Options Cannot Be Updated

**Current behaviour (working):** A Select, Radio, CheckBox, DataList, or MultiSelect field can exist without any options in Metadata. Admins can still open and save the Form Type without errors.

**New behaviour:** Saving a Form Type that contains an option-based field with no Metadata fails with a validation error.

**Potential impact:** If any such misconfigured field exists, admins cannot update anything else on that Form Type until the Metadata is fixed.

**Action needed before enabling:**
- Audit all Select/Radio/CheckBox/DataList/MultiSelect custom fields for missing Metadata.
- Add at least one option to any that are empty.

---

### Summary Table

| Issue | Who Is Affected | Severity |
|---|---|---|
| Required fields enforced server-side | Any record with a required field that was saved blank | High |
| Non-numeric values in NumberFields | Records with text stored in number fields | Medium |
| Unparseable dates in DateFields | Records with non-date text in date fields | Medium |
| Option-based fields without options | Form Type edits that include such fields | Low |

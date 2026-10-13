# NDA Settings Enhancements — Technical Design

## Overview

Four targeted fixes to the NDA settings workflow: dropdown clipping on the status dashboard, resign-on-override for inherited NDA overrides, validity type locking with expiry summary, and expired NDA edit fix. All changes are scoped to the `core/nda_configs` pack.

## 1. Actions Dropdown Clipping Fix

### Root Cause

The NDA Status dashboard table (`nda_status/index.html.erb`) uses Bootstrap's `.table-responsive` wrapper and `table.dataTable`. The global stylesheet (`styled_table.scss:143`) sets `overflow: hidden` on `table.dataTable`, and `.table-responsive` sets `overflow-x: auto`. When only one row exists, the dropdown has no room to expand downward within the table boundary and is clipped.

### Fix

In `nda_status/index.html.erb`:
- Added `style="overflow: visible;"` on the `.table-responsive` div
- Added `style="overflow: visible;"` on the `table` element
- Added `data-bs-display="static"` on the kebab dropdown toggle button

`data-bs-display="static"` alone was insufficient because `overflow: hidden` on the table still clips absolutely-positioned elements. The inline `overflow: visible` overrides the global stylesheet for this specific table.

### Files Changed

- `app/packs/core/nda_configs/views/nda_status/index.html.erb`

## 2. Resign Checkbox on Inherited NDA Override

### Problem

When a GP clicks "Set Own NDA" on a child folder that inherits its parent's NDA, the system creates a new `NdaConfig` without considering that LPs may have already accepted the inherited NDA. Those LPs lose access until they re-sign.

### Architecture

```
Parent Folder (NdaConfig A, enabled)
    └── Child Folder (mode: inherit → effective NDA = Config A)
            └── LP accepts Config A on Child Folder
                    └── NdaAcceptance { nda_config: A, investor: LP }

GP clicks "Set Own NDA" on Child:
    └── NdaConfigsController#new detects inherited acceptances
    └── Form shows resign checkbox with count
    └── On create:
        ├── resign_required=true  → fresh start, LP must re-sign
        └── resign_required=false → migrate_inherited_acceptances copies records
```

### Key Implementation Details

**Controller (`nda_configs_controller.rb`):**

`new` action:
- Detects `params[:override]` indicating GP clicked "Set Own NDA"
- Resolves `effective_nda_config` via the folder's ancestry walk **before** mode changes to "own"
- Counts accepted investors scoped to this folder via `Investor.owner_access_rights`
- Sets `@inherited_accepted_count` for the form

`create` action:
- Captures `effective_nda_before_override` before `@folder.update!(nda_inheritance_mode: "own")`
- Reads `resign_required` from the checkbox parameter (defaults to `false`)
- Creates `NdaConfigVersion` with `resign_required` flag
- When `resign_required=false`: calls `migrate_inherited_acceptances`

`migrate_inherited_acceptances(source_nda, target_nda)`:
- Scopes to investors with folder-level `AccessRight` via `Investor.owner_access_rights`
- Iterates accepted `NdaAcceptance` records on the source (inherited) NDA
- Creates copies on the target (new) NDA with `nda_version: 1`, preserving `accepted_at`
- Includes `entity_id` (required by `belongs_to :entity` on `NdaAcceptance`)
- Rescues `RecordNotUnique` / `RecordInvalid` for idempotency

**Form (`_form.html.erb`):**

- Resign checkbox is inside the NDA document upload section (not behind the version-bump warning)
- Visible only when: `!nda_config.persisted?` (new config) AND `inherited_accepted_count > 0`
- Uses `check_box_tag` (not form builder) because `resign_required` is not an NdaConfig attribute

### Data Flow

```
NdaAcceptance on Config A (parent)     NdaAcceptance on Config B (child)
┌──────────────────────────────┐       ┌──────────────────────────────┐
│ nda_config_id: A             │  ──>  │ nda_config_id: B             │
│ investor_id:   42            │  copy │ investor_id:   42            │
│ user_id:       7             │       │ user_id:       7             │
│ entity_id:     1097          │       │ entity_id:     1097          │
│ status:        "accepted"    │       │ status:        "accepted"    │
│ accepted_at:   2026-10-01    │       │ accepted_at:   2026-10-01    │
│ nda_version:   3             │       │ nda_version:   1             │
└──────────────────────────────┘       └──────────────────────────────┘
Original preserved (LP retains         Copy scoped to child folder's
access to other inherited folders)     new config
```

### Edge Cases Handled

- **Soft-deleted NdaConfig blocks unique index:** Cleanup uses `delete_all` (raw SQL DELETE) instead of `destroy` to bypass acts_as_paranoid scoping
- **FK constraints on cleanup:** Deletes dependent records (signatories, versions, acceptances) before the config
- **Missing `entity_id`:** `NdaAcceptance` has `belongs_to :entity` — migration copies `entity_id` from the source acceptance

### Files Changed

- `app/packs/core/nda_configs/controllers/nda_configs_controller.rb` — `new`, `create`, `migrate_inherited_acceptances`
- `app/packs/core/nda_configs/views/nda_configs/_form.html.erb` — resign checkbox UI

## 3. Validity Type Locking and Expiry Summary

### Problem

After LPs accept an NDA, the GP can switch validity types (e.g., "Until Revoked" to "Fixed Period"), retroactively changing how expiry is computed for existing acceptances. Additionally, GPs have no visibility into when existing acceptances expire.

### Implementation

**Validity locking (form-side only):**

In `_form.html.erb`:
- `validity_locked` is true when `nda_config.persisted? && @accepted_count > 0`
- All three validity type radio buttons get `disabled: validity_locked`
- A lock icon with explanation text appears above the radios
- Disabled radios are not submitted by the browser, so existing `validity_type` is preserved
- Within the same type, GP can still extend:
  - Fixed period: dropdown filters to options `>= current_days`
  - Specific date: date field sets `min` to current `validity_date`

**Expiry summary (controller + form):**

Controller `edit` action computes:
- For `fixed_period`: queries `accepted_at` from accepted `NdaAcceptance` records, computes `min + validity_days` and `max + validity_days` as `@earliest_expiry` / `@latest_expiry`
- For `specific_date`: no computation needed — `validity_date` is the same for all

Form displays:
- Fixed period: "Earliest expiry: [date] · Latest expiry: [date]"
- Specific date: "All NDAs expire on: [date]"

### Files Changed

- `app/packs/core/nda_configs/controllers/nda_configs_controller.rb` — `edit` action (expiry computation)
- `app/packs/core/nda_configs/views/nda_configs/_form.html.erb` — locked radios, filtered options, expiry summary

## 4. Expired NDA Edit Fix

### Root Cause

When an NDA has `specific_date` validity with a date in the past:

1. Form sets `min` attribute on the date input to the expired date (via the locking logic)
2. The `locale-date` Stimulus controller creates a hidden shadow `<input type="date">` (width:0, height:0) for localization
3. The shadow input inherits the `min` constraint
4. Current value (past date) < `min` (tomorrow) fails HTML5 validation
5. Browser cannot focus the hidden input to show the validation tooltip
6. Form submission is silently blocked — "nothing happens" on click

Browser console shows: `An invalid form control with name='' is not focusable` (x11)

### Fix

In `_form.html.erb`, line 201, changed the `date_min` computation for the locked case:

```ruby
# Before:
nda_config.validity_date.to_s

# After:
[nda_config.validity_date, Date.tomorrow].max.to_s
```

This clamps the `min` attribute to the later of the current validity_date and tomorrow:
- **NDA not expired:** `min` = current date (can only extend forward, same as before)
- **NDA expired:** `min` = tomorrow (GP can pick any future date to renew)

The server-side validation (`validity_date_must_be_future`) was already correct — it only fires on `new_record?` or `will_save_change_to_validity_date?`, so editing other fields on an expired NDA works without touching the date.

### Files Changed

- `app/packs/core/nda_configs/views/nda_configs/_form.html.erb` — `date_min` clamping

## Testing

### Manual Test Scenarios

1. **Dropdown clipping:** Open NDA Status for a folder with exactly 1 investor → click kebab → dropdown should render fully visible
2. **Resign checkbox:** Set up parent NDA → LP accepts on child (inherited) → GP clicks "Set Own NDA" on child → should see resign checkbox with count
3. **Acceptance migration:** Same as above, leave resign unchecked → save → child NDA Status should show LP as Accepted
4. **Resign required:** Same setup, check resign box → save → child NDA Status should show LP as Pending
5. **Validity locking:** Create NDA → LP accepts → edit NDA → validity type radios should be disabled with lock message
6. **Expiry summary (fixed_period):** Create NDA with 90-day fixed period → LP accepts → edit → should show earliest/latest expiry
7. **Expiry summary (specific_date):** Create NDA with specific date → edit → should show "All NDAs expire on: [date]"
8. **Expired NDA edit:** Set NDA to specific_date with past date (via console: `update_columns`) → edit → clicking Save should submit the form

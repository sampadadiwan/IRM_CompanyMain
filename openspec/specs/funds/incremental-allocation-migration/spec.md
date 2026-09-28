## Purpose

Lets support move a fund onto incremental since-inception allocation (and back) from the fund
formulas page, with a reviewable preview, safe apply, and a recorded history, instead of running
rake tasks.

## Requirements

### Requirement: Actions menu on the fund formulas page
The fund formulas page SHALL label its bulk dropdown "Actions". The menu SHALL keep the existing
Enable All, Disable All and Filter items. The incremental allocation and run check items SHALL
appear in it only for support users.

#### Scenario: Support user sees the new actions
- **WHEN** a support user opens the fund formulas page for a fund
- **THEN** the "Actions" menu lists Enable All, Disable All, Filter, "Incremental allocation" and "Suggest run checks"

#### Scenario: Non-support user sees only the existing actions
- **WHEN** a user without the support role opens the fund formulas page
- **THEN** the "Actions" menu lists Enable All, Disable All and Filter only

#### Scenario: Existing actions still work
- **WHEN** a user chooses Enable All from the "Actions" menu
- **THEN** every formula in the current list is enabled, as before the rename

### Requirement: Support-only access
Every incremental allocation page and action SHALL require the support role. A request from any
other user SHALL be refused without reading or changing anything.

#### Scenario: Non-support user calls an action directly
- **WHEN** a user without the support role requests a preview or apply URL for a fund
- **THEN** the request is refused as unauthorized and no operation record is created

### Requirement: Preview switching a fund to incremental allocation
Support SHALL be able to request a preview of switching a fund on. The preview SHALL run in the
background and SHALL NOT change any formula, account entry or fund setting. The finished preview
SHALL show:
- every formula that would be edited, with its current text, new text and new description
- every blocker, with the formula it concerns
- every warning
- every tracking starting value that would be corrected: formula, date, folio, current value, new value

#### Scenario: Preview of a fund that can be switched on
- **WHEN** support requests a preview for a fund with no blockers
- **THEN** an operation record for switching on is shown as in progress
- **AND** when it completes it shows the formula edits, warnings and starting values, and offers "Apply"
- **AND** the fund's formulas, entries and incremental flag are unchanged

#### Scenario: Preview of a blocked fund
- **WHEN** support requests a preview for a fund that has a blocker
- **THEN** the completed preview lists every blocker and does not offer "Apply"

#### Scenario: Fund already on incremental allocation
- **WHEN** support opens incremental allocation for a fund that is already switched on
- **THEN** the page says so and offers "Switch off" and "Recompute starting values" instead of switching on

### Requirement: Apply a previewed switch
Applying SHALL write exactly the changes the preview showed, all at once or not at all:
- the formula edits with their descriptions
- the corrected starting values
- the fund's incremental flag

Before writing, it SHALL plan the change again and refuse if the new plan differs from the
previewed one. The operation record SHALL store who applied it, when, and the result.

#### Scenario: Apply succeeds
- **WHEN** support applies a completed preview that has no blockers and nothing has changed since
- **THEN** the formulas, descriptions and starting values are updated, the fund is switched on
- **AND** the operation record shows status "applied", the applying user and the time

#### Scenario: Formulas changed after the preview
- **WHEN** a fund formula is edited after the preview and support then applies it
- **THEN** nothing is written, the record shows the apply was refused because the plan changed
- **AND** support is offered a new preview

#### Scenario: Apply fails part-way
- **WHEN** writing one of the changes raises an error during apply
- **THEN** none of the changes remain, the fund stays switched off, and the record shows the error

### Requirement: Refuse while the fund is busy
Applying a switch-on, switch-off or starting-value recompute SHALL be refused while the fund has an
allocation run that has not finished, or is part of an allocation run group that is still running.
At most one preview or apply SHALL be in progress per fund at a time.

#### Scenario: Allocation run in progress
- **WHEN** support applies a preview while an allocation run for that fund is still in progress
- **THEN** nothing is written and the page says to wait for the run to finish

#### Scenario: Second request while one is in progress
- **WHEN** support requests a preview while another preview or apply for the same fund is in progress
- **THEN** no new request is started and the page shows the one already in progress

### Requirement: Switch a fund off
Support SHALL be able to preview and apply switching a fund off. The preview SHALL list the formulas
and descriptions that will be restored from before the switch-on. A description edited by hand
since the switch-on SHALL be kept, and the preview SHALL warn that it was left as it is. Switch-off
SHALL keep the tracking formula fixes and their descriptions, and SHALL turn the fund's incremental
flag off. The same busy and changed-plan guards as switch-on SHALL apply.

#### Scenario: Switch off a fund
- **WHEN** support applies a switch-off preview for an incremental fund
- **THEN** the non-tracking formulas it edited get back their earlier text and description
- **AND** the tracking formulas are unchanged, the flag is off, and the record shows status "applied"

### Requirement: Recompute tracking starting values
For a fund's tracking formulas, support SHALL be able to preview and apply recomputing the stored
since-inception values on a date from full history. The date SHALL default to the latest date each
formula stored a value. The preview SHALL show current and recomputed values per folio. Apply SHALL
only overwrite existing stored entries, never create new ones.

#### Scenario: Recompute on the default date
- **WHEN** support previews recomputing starting values for a fund whose tracking formulas last stored values on 31 March 2026
- **THEN** the preview lists each tracking formula and folio with its value on 31 March 2026 and the recomputed value
- **AND** applying it overwrites those stored values and records the result

#### Scenario: Tracking formula has never stored a value
- **WHEN** a tracking formula has no stored entries
- **THEN** the preview lists it as having nothing to recompute and apply leaves it alone

### Requirement: Migration history
The incremental allocation page SHALL list the fund's operation records, newest first, with operation,
status, requesting user, applying user, times, and a link to the stored preview and result.
Records SHALL be kept after apply, refusal or failure.

#### Scenario: Viewing history
- **WHEN** support opens incremental allocation for a fund that was switched on and later off
- **THEN** both records are listed with their users, times and outcomes, and each opens its stored plan

### Requirement: Recommended steps
The incremental allocation page SHALL show the recommended order of steps for the fund, and mark each
step done when the fund's data shows it done:
1. run checks exist, including the check that stored Since Inception totals match history
2. a successful allocation run finished before the switch
3. the switch was applied
4. a successful allocation run finished after the switch

#### Scenario: Fund with checks but not yet switched
- **WHEN** support opens the page for a fund that has run checks and a successful run but is not switched on
- **THEN** steps 1 and 2 are marked done and step 3 offers the preview

### Requirement: Rake tasks use the same behaviour
The existing rake tasks SHALL keep their names, arguments and dry-run default, and SHALL produce the
same changes as the UI for the same fund:
- `allocation:enable_incremental`
- `allocation:disable_incremental`
- `allocation:describe_incremental`
- `allocation:reseed_carry_forward`

#### Scenario: Rake dry run matches the UI preview
- **WHEN** `allocation:enable_incremental[fund,<id>]` runs without APPLY for a fund
- **THEN** it prints the same formula edits, blockers, warnings and starting values the UI preview shows for that fund, and changes nothing

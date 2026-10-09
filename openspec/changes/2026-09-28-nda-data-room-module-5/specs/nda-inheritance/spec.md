# nda-inheritance

## Purpose

NDA flows from parent folder to child folders automatically. Each folder is in one of three
states: own NDA (solid lock), inherited (lock + "(Inherited)", uses ancestor's NdaConfig), or
opted out (no NDA even if parent has one). The Replace-Not-Stack rule means each folder resolves
to exactly one effective NDA, and acceptance is tied to the `NdaConfig` record — cross-folder
coverage is automatic.

## ADDED Requirements

### Requirement: Child folders inherit parent NDA automatically
When a GP sets an NDA on a folder, all child folders (and their children, recursively) SHALL
automatically be covered by the same NDA. No action is needed by the GP. The inherited NDA uses
the parent's `NdaConfig`: same document, same validity, same acceptance method, same contact
email.

#### Scenario: Direct child inherits parent NDA
- **GIVEN** the GP has set NDA-A on "Data Room"
- **WHEN** an LP navigates to child folder "Deal Pipeline" (which has no own NdaConfig)
- **THEN** the NDA acceptance screen for NDA-A is shown

#### Scenario: Grandchild inherits grandparent NDA
- **GIVEN** the GP has set NDA-A on "Data Room"
- **AND** "Deal Pipeline" is a child of "Data Room" with no own NDA
- **AND** "TechCo Acquisition" is a child of "Deal Pipeline" with no own NDA
- **WHEN** an LP navigates to "TechCo Acquisition"
- **THEN** the NDA acceptance screen for NDA-A is shown

#### Scenario: No NDA in ancestry
- **GIVEN** no folder in the ancestry chain has an NDA configured
- **WHEN** an LP navigates to the folder
- **THEN** the folder contents are shown directly (no NDA screen)

### Requirement: Replace, Not Stack — child override replaces parent NDA
When a child folder has its own NDA (override), it SHALL replace the parent's NDA entirely. The
LP SHALL NOT need to accept both the parent's NDA and the child's NDA. Children of the override
folder SHALL inherit the child's NDA, not the grandparent's.

#### Scenario: Child override replaces parent NDA
- **GIVEN** "Data Room" has NDA-A and "Fund Financials" (child) has its own NDA-B
- **WHEN** an LP navigates to "Fund Financials"
- **THEN** the NDA acceptance screen shows NDA-B only (not NDA-A)

#### Scenario: Grandchild inherits child's override, not grandparent's
- **GIVEN** "Data Room" has NDA-A, "Fund Financials" has NDA-B, "Q3 Report" is a child of
  "Fund Financials" with no own NDA
- **WHEN** an LP navigates to "Q3 Report"
- **THEN** the NDA acceptance screen shows NDA-B (inherited from Fund Financials)

#### Scenario: LP does not need to accept both NDAs
- **GIVEN** "Data Room" has NDA-A and "Fund Financials" has its own NDA-B
- **WHEN** an LP accepts NDA-B on "Fund Financials"
- **THEN** the LP is NOT asked to also accept NDA-A for "Fund Financials"

### Requirement: Acceptance tied to NdaConfig covers all inheriting folders
When an LP accepts an NDA, the acceptance is tied to the `NdaConfig` record. All folders
that resolve to the same effective `NdaConfig` SHALL be covered by the same acceptance.
The LP SHALL NOT be asked to accept the same NDA again on a different folder that inherits it.

#### Scenario: Accepting on parent covers inheriting child
- **GIVEN** "Data Room" has NDA-A and "Deal Pipeline" inherits NDA-A
- **WHEN** an LP accepts NDA-A on "Data Room"
- **AND** the LP navigates to "Deal Pipeline"
- **THEN** the folder contents are shown directly (NDA-A already accepted)

#### Scenario: Accepting on child covers parent (same config)
- **GIVEN** "Data Room" has NDA-A and "Deal Pipeline" inherits NDA-A
- **WHEN** an LP accepts NDA-A via the "Deal Pipeline" acceptance screen
- **AND** the LP navigates to "Data Room"
- **THEN** the folder contents are shown directly (NDA-A already accepted)

#### Scenario: Different configs require separate acceptance
- **GIVEN** "Data Room" has NDA-A and "Fund Financials" has its own NDA-B
- **WHEN** an LP has accepted NDA-A but not NDA-B
- **AND** the LP navigates to "Fund Financials"
- **THEN** the NDA acceptance screen shows NDA-B (different config, separate acceptance needed)

### Requirement: Opt-out stops the inheritance chain
A folder that is explicitly opted out SHALL have no NDA requirement, even if its parent has
one. Children of an opted-out folder SHALL also have no NDA unless they have their own NdaConfig.
Opt-out stops the lookup chain — children do NOT inherit the grandparent's NDA through
an opted-out folder.

#### Scenario: Opted-out folder has no NDA
- **GIVEN** "Data Room" has NDA-A and "Marketing" is opted out
- **WHEN** an LP navigates to "Marketing"
- **THEN** the folder contents are shown directly (no NDA screen)

#### Scenario: Child of opted-out folder has no NDA
- **GIVEN** "Data Room" has NDA-A, "Marketing" is opted out, and "Press Releases" is a child of
  "Marketing" with no own NDA
- **WHEN** an LP navigates to "Press Releases"
- **THEN** the folder contents are shown directly (opt-out stops the chain — grandparent's
  NDA-A is not inherited)

#### Scenario: Child of opted-out folder can have own NDA
- **GIVEN** "Marketing" is opted out and "Sensitive Materials" (child of Marketing) has its own
  NDA-C
- **WHEN** an LP navigates to "Sensitive Materials"
- **THEN** the NDA acceptance screen shows NDA-C

### Requirement: GP sees inheritance status on Settings tab
When the GP opens NDA Settings on a folder that inherits its NDA, the Settings tab SHALL show:
the source folder name, parent's NDA details (read-only), and three radio options.

#### Scenario: Inherited folder Settings tab
- **WHEN** the GP opens NDA Settings on "Deal Pipeline" which inherits NDA-A from "Data Room"
- **THEN** the Settings tab shows: "This folder inherits NDA from: Data Room"
- **AND** the parent's NDA details are shown read-only (document name, validity, method)
- **AND** three radio options: "Use parent's NDA" (selected), "Set different NDA for this
  folder", "No NDA required for this folder"

#### Scenario: Opted-out folder Settings tab
- **WHEN** the GP opens NDA Settings on an opted-out folder whose parent has NDA-A
- **THEN** the Settings tab shows: the parent's NDA info and that this folder is opted out
- **AND** "No NDA required" is selected
- **AND** the GP can switch to "Use parent's NDA" or "Set different NDA"

#### Scenario: Own NDA folder with parent NDA — shows revert option
- **WHEN** the GP opens NDA Settings on "Fund Financials" which has its own NDA-B and whose
  parent "Data Room" has NDA-A
- **THEN** the standard Module 1 form is shown (NDA-B settings)
- **AND** an option to "Remove this NDA and use parent's" is available

### Requirement: GP overrides child folder with different NDA
Selecting "Set different NDA for this folder" SHALL expand the full NDA configuration form. On
save, a new `NdaConfig` SHALL be created for the folder and `nda_inheritance_mode` set to `own`.
Children of this folder SHALL now inherit the new NDA.

#### Scenario: Override creates own config
- **GIVEN** "Deal Pipeline" inherits NDA-A from "Data Room"
- **WHEN** the GP selects "Set different NDA for this folder", uploads NDA-B, and saves
- **THEN** a new `NdaConfig` is created for "Deal Pipeline" with NDA-B
- **AND** "Deal Pipeline" has `nda_inheritance_mode = own`
- **AND** the folder tree shows a solid lock on "Deal Pipeline"

#### Scenario: Children of override inherit new NDA
- **GIVEN** the GP overrode "Deal Pipeline" with NDA-B
- **AND** "TechCo Acquisition" is a child of "Deal Pipeline" with no own NDA
- **WHEN** an LP navigates to "TechCo Acquisition"
- **THEN** the NDA acceptance screen shows NDA-B (not grandparent's NDA-A)

### Requirement: GP opts child folder out of NDA
Selecting "No NDA required for this folder" SHALL set `nda_inheritance_mode = opt_out`. A
confirmation prompt SHALL warn the GP. Children of the opted-out folder SHALL also have no NDA.

#### Scenario: Opt-out with confirmation
- **WHEN** the GP selects "No NDA required" on an inheriting folder
- **THEN** a confirmation prompt appears: "LPs will be able to access this folder without
  accepting an NDA. Are you sure?"
- **AND** on confirmation, `nda_inheritance_mode` is set to `opt_out`

#### Scenario: Opt-out removes lock icon
- **GIVEN** a folder was inheriting NDA-A (lock + "(Inherited)")
- **WHEN** the GP opts it out
- **THEN** the folder tree shows no lock icon for this folder

### Requirement: New folder auto-inherits parent NDA
A new folder created inside an NDA-protected parent SHALL automatically inherit the NDA. The
default `nda_inheritance_mode` SHALL be `inherit`.

#### Scenario: New folder inherits parent NDA
- **GIVEN** "Data Room" has NDA-A
- **WHEN** the GP creates a new folder "New Deal" inside "Data Room"
- **THEN** "New Deal" has `nda_inheritance_mode = inherit`
- **AND** the effective NDA is NDA-A
- **AND** the folder tree shows a lock + "(Inherited)" on "New Deal"

#### Scenario: New folder inside opted-out parent has no NDA
- **GIVEN** "Marketing" is opted out
- **WHEN** the GP creates a new folder "Campaign" inside "Marketing"
- **THEN** "Campaign" has `nda_inheritance_mode = inherit`
- **AND** the effective NDA is nil (opted-out parent stops the chain)
- **AND** no lock icon is shown

### Requirement: Removing parent NDA uncascades to inheriting children
When the GP disables NDA on a parent folder, all child folders that were inheriting SHALL lose
their NDA. Children with their own NDA SHALL NOT be affected. Children that were opted out SHALL
NOT be affected.

#### Scenario: Disabling parent NDA removes inherited NDA from children
- **GIVEN** "Data Room" has NDA-A, "Deal Pipeline" inherits, "Fund Financials" has own NDA-B,
  "Marketing" is opted out
- **WHEN** the GP disables NDA-A on "Data Room"
- **THEN** "Deal Pipeline" has no NDA (was inheriting, parent no longer has NDA)
- **AND** "Fund Financials" still has NDA-B (own config, unaffected)
- **AND** "Marketing" is still opted out (unaffected)
- **AND** the folder tree updates: "Deal Pipeline" loses lock, "Fund Financials" keeps
  solid lock

#### Scenario: LP access after parent NDA removal
- **GIVEN** the GP disabled NDA-A on "Data Room"
- **WHEN** an LP navigates to "Deal Pipeline" (which was inheriting NDA-A)
- **THEN** the folder contents are shown directly (no NDA screen — NDA is gone)

### Requirement: Folder tree inheritance indicators
The folder tree SHALL show different lock icons for own NDA vs inherited NDA. Own NDA SHALL show
a solid lock. Inherited NDA SHALL show a solid lock with "(Inherited)" text label and a tooltip.
Opted-out and unprotected folders SHALL show no icon. Icons SHALL be visible to GP/admin only.

#### Scenario: Solid lock for own NDA
- **WHEN** a folder has `nda_inheritance_mode = own` and an enabled NdaConfig
- **THEN** the folder tree shows a solid lock icon

#### Scenario: Lock with "(Inherited)" label for inherited NDA
- **WHEN** a folder has `nda_inheritance_mode = inherit` and an effective NdaConfig is present
- **THEN** the folder tree shows a solid lock icon with "(Inherited)" text label

#### Scenario: Inherited lock tooltip shows source
- **WHEN** the GP hovers over an inherited lock on "TechCo Acquisition" (inherits from "Deal
  Pipeline")
- **THEN** a tooltip shows "Inherits NDA from: Deal Pipeline"

#### Scenario: No icon for opted-out folder
- **WHEN** a folder is opted out
- **THEN** no lock icon is shown

#### Scenario: Icons visible to GP only
- **WHEN** an LP views the folder tree
- **THEN** no lock icons are shown (LP does not see NDA indicators)

### Requirement: Status tab on inherited folder shows parent config data
When the GP opens the Status tab on a folder that inherits its NDA, the Status tab SHALL show
the user statuses from the effective (parent's) `NdaConfig`. A heading SHALL clarify
which config is being shown.

#### Scenario: Status tab on inherited folder
- **GIVEN** "Deal Pipeline" inherits NDA-A from "Data Room"
- **WHEN** the GP opens the Status tab on "Deal Pipeline"
- **THEN** the heading shows "Showing NDA status for: Data Room"
- **AND** the user status table shows the same data as the Status tab on "Data Room"

### Requirement: Reverting from own to inherited
A folder with its own NDA SHALL allow the GP to revert to the parent's NDA. On revert, the
own `NdaConfig` SHALL be soft-deleted and `nda_inheritance_mode` set to `inherit`.

#### Scenario: GP reverts from own to parent NDA
- **GIVEN** "Deal Pipeline" has its own NDA-B and parent "Data Room" has NDA-A
- **WHEN** the GP selects "Remove this NDA and use parent's" and confirms
- **THEN** NDA-B config is soft-deleted
- **AND** `nda_inheritance_mode` is set to `inherit`
- **AND** the folder tree changes from solid lock to lock + "(Inherited)"
- **AND** the effective NDA is NDA-A

#### Scenario: Existing acceptances preserved on revert
- **GIVEN** users had accepted NDA-B on "Deal Pipeline"
- **WHEN** the GP reverts to parent's NDA-A
- **THEN** NDA-B acceptance records are preserved for audit
- **AND** users visiting "Deal Pipeline" see NDA-A acceptance screen (if they haven't accepted
  NDA-A)

### Requirement: Authorization
Only GPs with folder management rights SHALL be able to change a folder's inheritance mode
(override, opt-out, revert). LP users SHALL NOT see inheritance controls.

#### Scenario: GP can change inheritance mode
- **WHEN** a GP with folder management rights opens NDA Settings on an inherited folder
- **THEN** the three radio options are shown and functional

#### Scenario: LP cannot change inheritance mode
- **WHEN** an LP user attempts to access the NDA Settings URL
- **THEN** the request is denied by policy

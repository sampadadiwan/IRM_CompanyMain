# nda-folder-config

## MODIFIED Requirements

### Requirement: NDA Settings modal adapts for inheritance context
The NDA Settings modal SHALL detect the folder's inheritance state and render the appropriate
variant. When the folder inherits an NDA from an ancestor, the modal SHALL show the inherited
variant (source folder name, read-only NDA details, three radio options) instead of the
standard configuration form. When the folder has its own NDA and the parent also has an NDA,
the modal SHALL show the standard form plus a "Remove this NDA and use parent's" option.

#### Scenario: Inherited folder shows inheritance variant instead of form
- **WHEN** the GP opens NDA Settings on a folder that inherits NDA from an ancestor
- **THEN** the modal shows the inherited variant with source folder name and read-only details
- **AND** the standard NDA configuration form is NOT shown unless the GP selects "Set different
  NDA for this folder"

#### Scenario: Own NDA folder with parent NDA shows revert option
- **WHEN** the GP opens NDA Settings on a folder that has its own NdaConfig and whose parent
  also has an NdaConfig
- **THEN** the standard Module 1 configuration form is shown
- **AND** a "Remove this NDA and use parent's" option is visible below the form

#### Scenario: Own NDA folder without parent NDA shows standard form only
- **WHEN** the GP opens NDA Settings on a folder that has its own NdaConfig and whose parent
  has no NDA
- **THEN** the standard Module 1 configuration form is shown
- **AND** no "Remove this NDA and use parent's" option is visible

### Requirement: NDA Settings controller handles inheritance transitions
The NDA Settings controller SHALL handle `inheritance_choice` parameter to manage state
transitions: creating own config (set_own), reverting to parent (use_parent), or opting out
(opt_out). Each transition SHALL update both the `NdaConfig` record and the folder's
`nda_inheritance_mode` atomically.

#### Scenario: Controller creates own config on override
- **WHEN** the GP submits NDA Settings with `inheritance_choice = set_own` and valid NDA config
  params
- **THEN** a new `NdaConfig` is created for the folder (owner = folder, polymorphic)
- **AND** the folder's `nda_inheritance_mode` is set to `own`

#### Scenario: Controller soft-deletes config on revert to parent
- **WHEN** the GP submits NDA Settings with `inheritance_choice = use_parent`
- **THEN** the folder's own `NdaConfig` is soft-deleted
- **AND** the folder's `nda_inheritance_mode` is set to `inherit`

#### Scenario: Controller sets opt-out mode
- **WHEN** the GP submits NDA Settings with `inheritance_choice = opt_out`
- **THEN** any existing own `NdaConfig` is soft-deleted
- **AND** the folder's `nda_inheritance_mode` is set to `opt_out`

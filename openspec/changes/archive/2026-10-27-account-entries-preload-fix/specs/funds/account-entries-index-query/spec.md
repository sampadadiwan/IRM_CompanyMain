# Spec Delta

## Purpose

Keeps the Account Entries list cheap on very large ledgers by reading the entries on their own, fetching related fund, investor, commitment and KYC details only for the rows shown, and opening the list on one fund instead of every fund.

## ADDED Requirements

### Requirement: List content is unchanged
For the funds being shown, the Account Entries list SHALL show the same rows, in the same order and with the same fund, investor, commitment and KYC details on each row as before this change.

#### Scenario: Related details still shown
- **WHEN** a fund admin opens the Account Entries list for a fund that has entries with a commitment and investor KYC
- **THEN** each row shows its fund, investor, commitment and KYC details

#### Scenario: Entry without optional relations
- **WHEN** an entry has no investor or no commitment
- **THEN** the row is still listed with those details blank

### Requirement: Main query does not read related tables
The database request that selects the page of account entries SHALL read columns from the account entries table only. Related fund, investor, commitment and KYC records SHALL be fetched in separate look-ups limited to the entries on the page.

#### Scenario: No wide join on the main request
- **WHEN** the Account Entries list is opened
- **THEN** no request selects columns of funds, investors, commitments or investor KYCs in the same statement that selects the account entries

#### Scenario: Look-ups bounded by page size
- **WHEN** the list shows a page of 5 entries and then a page of 10 entries
- **THEN** the number of database requests for related records is the same for both

### Requirement: Access scoping is preserved
The list SHALL continue to show only entries that the user's role and entity are allowed to see.

#### Scenario: Employee with limited fund access
- **WHEN** an employee with access to one fund opens the list
- **THEN** only entries of that fund are shown, with no duplicate rows

#### Scenario: Other entity's data
- **WHEN** a user from a different entity opens the list
- **THEN** none of the first entity's entries are shown

### Requirement: The list opens on the first fund
When the list is opened without any fund selected and not narrowed to an import, investor, folio, commitment or parent, the list SHALL be limited to the first fund the user can access (fund ordering), the fund filter SHALL show that fund as selected, and the page SHALL say which fund is shown. A fund, or several funds, that the user selects SHALL be used exactly as given.

#### Scenario: No fund chosen
- **WHEN** a fund admin opens Reports → Account Entries with no fund selected
- **THEN** only the entries of the entity's first fund are listed
- **AND** the filter shows that fund as selected

#### Scenario: The page says which fund is shown
- **WHEN** the default fund was applied
- **THEN** a notice names the fund and points to "All Funds"
- **AND** no notice is shown when the user picked a fund or All Funds

#### Scenario: A narrowed list keeps every fund
- **WHEN** the list is opened with only an import, investor, folio, commitment or parent filter
- **THEN** no default fund is applied and the filter shows "All Funds"

#### Scenario: Deleting an entry
- **WHEN** a user deletes an account entry
- **THEN** they return to the list of that entry's fund

#### Scenario: Employee default is a fund they can access
- **WHEN** an employee who has access only to the entity's second fund opens the list with no fund selected
- **THEN** the entries of that second fund are listed

#### Scenario: User picks a fund
- **WHEN** a user opens the list for a specific fund
- **THEN** that fund's entries are listed and no default is added

#### Scenario: User chooses All Funds
- **WHEN** a user chooses "All Funds" in the fund filter and searches
- **THEN** the entries of every fund are listed and no default is added

#### Scenario: User picks several funds
- **WHEN** a user filters with fund in X, Y
- **THEN** the entries of both funds are listed

#### Scenario: Actions follow the fund shown
- **WHEN** the list opened on the default fund
- **THEN** "Delete Results" and "Export All" are for that fund
- **AND** after the user chooses "All Funds" they are not limited to a fund

#### Scenario: Entity without funds
- **WHEN** an entity with no funds opens the list
- **THEN** the list is empty

#### Scenario: Fund of another entity
- **WHEN** a user selects a fund that belongs to a different entity
- **THEN** no entries are listed and the fund is not replaced by a default

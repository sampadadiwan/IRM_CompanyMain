# funds/evergreen-class-nav Specification

## Purpose

Defines how an evergreen fund with several classes gets a separate, fair NAV per class: how the
shared portfolio is split between classes, and which lines belong to one class only.

## Requirements

### Requirement: One NAV per class per NAV date
The system SHALL draft one NAV and one NAV per unit for every class of an evergreen fund on each NAV
date. Each class's NAV SHALL equal its share of the shared lines (investments at fair value, cash,
other assets, other liabilities) minus its own lines (management fee payable, performance fee
payable and accrued, class expenses payable, money for orders not yet dealt in that class).

#### Scenario: Two classes, different fees
- **WHEN** Class A (60,000 units, previous NAV ₹600 Cr) and Class B (20,000 units, previous NAV ₹400 Cr) owe nothing at the previous NAV and the shared lines total ₹1,100 Cr
- **THEN** Class A's share is ₹660 Cr and Class B's ₹440 Cr, and each class's own fees come off only that class

#### Scenario: One class
- **WHEN** the fund has one class
- **THEN** that class receives 100% of the shared lines

### Requirement: Shared lines split by each class's stake
The system SHALL split the shared lines in proportion to each class's stake. A class's stake is
its previous approved NAV plus its own lines owed at that NAV (management fee payable, performance
fee payable and accrued, class expenses payable), scaled by its units on the NAV date ÷ its units at
the previous NAV, minus the payments of its own lines made since the previous NAV. For a class with
no previous NAV or no previous units, the stake SHALL be its units × its initial price.

#### Scenario: An unpaid fee does not move value between classes
- **WHEN** Class A and Class B each have a ₹50 Cr stake in a ₹100 Cr shared pool, Class A owes a ₹1 Cr fee not yet paid, and nothing else changes before the next NAV
- **THEN** the next NAV gives Class A ₹49 Cr and Class B ₹50 Cr

#### Scenario: Paying a fee from shared cash reduces only the owing class
- **WHEN** Class A then pays its ₹1 Cr fee from the fund's cash, and nothing else changes
- **THEN** the following NAV still gives Class A ₹49 Cr and Class B ₹50 Cr

#### Scenario: Units issued since the previous NAV
- **WHEN** a class issued units on a dealing date after its previous NAV
- **THEN** its stake grows by those units at its previous gross value per unit

#### Scenario: Previous NAV uploaded
- **WHEN** the previous NAV of every class was uploaded (no fee lines)
- **THEN** each stake is the uploaded NAV scaled for units, less payments since, the same as splitting by previous NAV

#### Scenario: Approved NAVs are not re-split
- **WHEN** the new split rule is installed
- **THEN** NAVs already approved keep their figures; only NAVs drafted afterwards use the new split

### Requirement: Class-only expenses
The system SHALL let each class name a class expenses ledger entry and a class expenses paid ledger
entry. When named, the class's NAV SHALL carry a "Class expenses payable" line equal to the previous
payable plus that class's expenses since the previous NAV minus its payments since. Payments SHALL
reduce only that class's stake. A class without named entries SHALL show no such line.

#### Scenario: Expense charged to one class
- **WHEN** Class B's expenses entry records ₹40,00,000 before the NAV date
- **THEN** Class B's NAV falls by ₹40,00,000 and Class A's NAV is the same as without the expense

#### Scenario: Expense paid
- **WHEN** Class B's expenses paid entry records ₹40,00,000 and the fund's cash falls by the same amount
- **THEN** Class B's payable falls to zero, its NAV is unchanged by the payment, and Class A's NAV is unchanged

#### Scenario: Overpaid
- **WHEN** Class B's payments exceed what it owed
- **THEN** Class B's class expenses payable is negative and no other class is affected

#### Scenario: Override
- **WHEN** a user overrides Class B's class expenses payable with a reason
- **THEN** the override is kept on re-drafting, as for other lines

### Requirement: Class expense entry names are validated
The system SHALL require both class expense entries or neither, each up to 125 characters, and
SHALL refuse a name already used by another class's expense entries or by the fund's own ledger
settings (cash, other assets, other liabilities, fee paid entries).

#### Scenario: Only one entry named
- **WHEN** a user names a class expenses entry without a paid entry
- **THEN** the settings are refused with "Class B needs both a class expenses entry and a class expenses paid entry, or neither"

#### Scenario: Name used by another class
- **WHEN** Class B's expense entry name equals Class A's
- **THEN** the settings are refused with "Class B's expense entry 'Class A Servicing Fee' is already used by Class A — each class needs its own entries"

### Requirement: Unclaimed class-looking ledger entries are flagged
The system SHALL warn on a NAV draft when the fund's ledger has, on or before the NAV date, an entry
whose name begins with "Class " that no class uses as an expense entry, so the expense is not
silently ignored.

#### Scenario: Entry not named on any class
- **WHEN** the ledger has "Class B Servicing Fee" and no class names it
- **THEN** the NAV page shows "Ledger entry 'Class B Servicing Fee' looks class-specific but no class uses it — name it on the class or it is ignored"

# funds/fund-nav Specification

## Purpose

Produces an approved NAV per unit class per date for open-ended funds. It is drafted from CapHive data, can be overridden or uploaded, and is approved by a second person before anything is priced on it.

## Requirements

### Requirement: Draft a NAV per unit class
The system SHALL draft one NAV per unit class for a chosen NAV date of an open-ended fund. The draft SHALL have these lines:
- Investments at fair value
- Cash
- Other assets
- Management fee payable
- Performance fee payable (crystallised, unpaid)
- Accrued performance fee (not yet crystallised)
- Other liabilities

Cash, other assets and other liabilities SHALL be read as the latest fund-level ledger balance on or before the NAV date, under the account entry names configured in the fund's open-ended settings. The defaults are "Cash In Hand" for cash, "Net Current Assets" for other assets and "Other Liabilities" for other liabilities.

It SHALL compute:
- NAV = assets − liabilities
- units outstanding = sum of the class's fund units issued on or before the NAV date
- NAV per unit = NAV ÷ units outstanding

Each line SHALL record where its value came from.

#### Scenario: Missing portfolio valuation
- **WHEN** a holding of the fund has no valuation on or before the NAV date
- **THEN** no draft is created and the admin sees "No valuation for <company> on or before 31 Oct 2026 — add one or upload the NAV"

#### Scenario: Draft from CapHive data
- **WHEN** a fund admin drafts the NAV for 31 Oct 2026 for a fund with one class "A" whose holdings have fair value ₹95,00,00,000, cash ₹8,00,00,000, accrued fees ₹50,00,000, other liabilities ₹30,00,000 and 1,00,000 units outstanding
- **THEN** a draft NAV for class A dated 31 Oct 2026 shows NAV ₹102,20,00,000 and NAV per unit ₹10,220.00

#### Scenario: Several classes
- **WHEN** a fund with classes "A" and "B" drafts a NAV
- **THEN** one draft is created per class:
  - fund-wide assets and liabilities are split by each class's stake (see `funds/evergreen-class-nav` › Shared lines split by each class's stake);
  - management and performance fees come from that class alone;
  - each class has its own NAV per unit.

#### Scenario: Class with no units
- **WHEN** a class has zero units outstanding on the NAV date
- **THEN** its draft shows NAV per unit as the class's initial price from the open-ended settings and is labelled "No units outstanding — initial price"

### Requirement: Override a NAV line
The system SHALL allow any line of a draft NAV to be overridden with a value and a reason of at most 255 characters, recomputing NAV and NAV per unit and showing the override and reason next to the line.

#### Scenario: Override with reason
- **WHEN** a fund admin overrides "Accrued management fee" to ₹50,00,000 with reason "per admin statement"
- **THEN** the line shows ₹50,00,000 marked overridden with that reason and NAV per unit is recomputed

#### Scenario: Override without reason
- **WHEN** a fund admin overrides a line without a reason
- **THEN** the override is not saved and the reason field shows an error

### Requirement: Upload a NAV
The system SHALL accept an upload with columns Unit class, NAV date, NAV, Units outstanding, NAV per unit, creating a draft NAV marked "Source: uploaded" per row and reporting per-row errors in the upload results.

#### Scenario: Upload administrator NAV
- **WHEN** a fund admin uploads a row "A, 30 Sep 2026, 98,26,00,000, 98,450, 9,980.69"
- **THEN** a draft NAV for class A dated 30 Sep 2026 exists with source Uploaded and NAV per unit 9,980.69

#### Scenario: Upload row inconsistent with units
- **WHEN** an uploaded row's NAV ÷ units outstanding differs from its NAV per unit by more than 0.01
- **THEN** that row is rejected with the error "NAV per unit does not equal NAV ÷ units outstanding"

### Requirement: Approve a NAV with the approver role
The system SHALL allow a draft NAV to be approved only by a user who holds the approver role and fund update rights. An approver MAY approve a NAV they prepared or overrode (small funds); the audit trail SHALL record the draft, every override (who, when, old → new, reason) and the approval, noting when the approver also prepared or overrode it. An approved NAV SHALL be read-only.

#### Scenario: Approved by a colleague
- **WHEN** a user with the approver role who did not prepare the draft clicks Approve
- **THEN** the NAV status becomes Approved, the approver and time are recorded, and its lines can no longer be edited

#### Scenario: Approver approves the NAV they prepared
- **WHEN** a user with the approver role approves a draft they prepared
- **THEN** the NAV is approved and its audit trail notes "approver also prepared this NAV"

#### Scenario: Without the approver role
- **WHEN** a user without the approver role views a draft NAV
- **THEN** the Approve action is not available, the page says "Needs the approver role", and a direct request is refused with "Only an approver can approve a NAV"

### Requirement: Reopen only unused NAVs
The system SHALL allow an approved NAV to be reopened to draft only when no confirmed dealing date used it.

#### Scenario: Reopen unused NAV
- **WHEN** an approver reopens an approved NAV that no confirmed dealing date used
- **THEN** it returns to Draft and can be edited and re-approved

#### Scenario: Reopen used NAV
- **WHEN** an approver views an approved NAV used by the confirmed dealing date of 2 Nov 2026
- **THEN** Reopen is disabled with "Used by dealing date 2 Nov 2026 — cannot reopen"

### Requirement: Flag NAVs whose inputs changed
The system SHALL mark a NAV stale when a portfolio valuation, fund unit or fund account entry dated on or before its NAV date is created, changed or deleted after the NAV was drafted. A stale draft SHALL offer Recalculate. A stale approved NAV SHALL keep its values and show an information note.

#### Scenario: Draft becomes stale
- **WHEN** a portfolio valuation dated 30 Oct 2026 is changed after the 31 Oct draft was created
- **THEN** the draft shows "Inputs changed since drafted — Recalculate"

#### Scenario: Approved NAV inputs change
- **WHEN** a fund unit dated 15 Oct 2026 is added after the 31 Oct NAV was approved
- **THEN** the approved NAV values are unchanged and it shows "Inputs changed after approval"

### Requirement: Investors see only approved NAVs
The system SHALL never show a draft NAV to an investor user.

#### Scenario: Latest NAV is a draft
- **WHEN** the latest NAV for class A is a draft and the previous approved NAV is dated 30 Sep 2026
- **THEN** the investor sees NAV per unit as of 30 Sep 2026

### Requirement: Fee payments settle the class that owed them
The system SHALL split a fund-level management or performance fee payment between unit classes in proportion to what each class owed before the payment, so a class that owed nothing is never credited. An excess over the total owed, or a payment when nothing is owed, SHALL be split by the classes' share of fund value.

#### Scenario: Only one class owed the fee
- **WHEN** only Class A owed a ₹2 Cr performance fee and it is paid, with no market movement
- **THEN** the next NAVs are Class A ₹48 Cr and Class B ₹50 Cr, exactly as before the payment

#### Scenario: Part payment
- **WHEN** Class A owes ₹9,00,000 and Class B ₹3,00,000 of management fee and ₹6,00,000 is paid
- **THEN** Class A is credited ₹4,50,000 and Class B ₹1,50,000

### Requirement: Money for orders not yet dealt is kept out of the NAV
The system SHALL add a liability line "Money received for orders not yet dealt" to each computed class NAV: money received on or before the NAV date for subscriptions dealt after it (charged to the order's class), plus the payout of redemptions dealt on or before the NAV date but not yet paid, whose units SHALL be left out of units outstanding. An uploaded NAV SHALL be taken as given.

#### Scenario: Pre-funded money before its dealing date
- **WHEN** ₹5 Cr received on 25 October for the 2 November dealing date is in the fund's cash on the 31 October NAV
- **THEN** the line shows ₹5 Cr and NAV per unit is ₹10,220, not ₹10,720

#### Scenario: Dealt but unpaid redemption
- **WHEN** 1,000 units were dealt on 2 November at ₹10,220 and are paid on 3 December
- **THEN** the 30 November NAV holds ₹1,02,20,000 in the line and counts 99,000 units outstanding


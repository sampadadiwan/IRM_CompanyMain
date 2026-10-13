# Spec Delta

## Purpose

Gives fund admins screens built for running an evergreen fund, chosen by the fund's evergreen flag: Overview, Dealing, Orders, NAV, Investors, Fees and Settings. It also applies evergreen labels everywhere, including on the settlement records underneath.

## ADDED Requirements

### Requirement: Screens chosen by the fund's flag
For an evergreen fund the system SHALL show the GP tabs Overview, Dealing, Orders, NAV, Investors, Fees, Portfolio, Ledger, Documents and Settings, and a header with NAV, units, NAV per unit, net flows for the quarter to date and the next dealing date. For a closed-end fund it SHALL show today's tabs and header unchanged.

#### Scenario: Evergreen tabs
- **WHEN** a fund admin opens an evergreen fund
- **THEN** the tabs are Overview, Dealing, Orders, NAV, Investors, Fees, Portfolio, Ledger, Documents and Settings, and there are no Commitments, Calls or Distributions tabs

#### Scenario: Closed-end tabs unchanged
- **WHEN** a fund admin opens a closed-end fund
- **THEN** the tabs and header are the same as before this change

### Requirement: Funds list card
The system SHALL show an evergreen fund on the funds list with an Evergreen badge, NAV, NAV per unit, net flows for the quarter to date and the next dealing date, instead of committed, called and distributed.

#### Scenario: Card
- **WHEN** a fund admin views the funds list with one evergreen and one closed-end fund
- **THEN** the evergreen card shows the Evergreen badge and NAV figures, and the closed-end card is unchanged

### Requirement: Overview
The Overview SHALL show:
- the latest approved NAV and NAV per unit per class, noting any newer draft;
- net flows for the quarter to date, with money in and money out;
- the next dealing date's cut-off, step bar and what's needed now;
- queued redemptions against the gate, and cash from the ledger;
- a 12-month NAV-per-unit trend per class.

#### Scenario: Overview figures
- **WHEN** the latest approved NAV is ₹101,50,00,000 at 30 Nov 2026 with NAV per unit ₹10,160.94, quarter-to-date subscriptions allotted are ₹5,00,00,000 and redemptions paid are ₹5,11,00,000
- **THEN** the Overview shows NAV ₹101.50 Cr, NAV/unit ₹10,160.94 and net flows −₹0.11 Cr

#### Scenario: Newer draft noted
- **WHEN** a 31 Dec 2026 NAV is in draft
- **THEN** the Overview still shows the 30 Nov approved NAV, with "Draft 31 Dec awaiting approval"

### Requirement: Order book
Orders SHALL list every order, with filters by type, status, class and dealing date. It SHALL have a redemption queue panel that lists open redemptions in queue order, with units, indicative value, running total and the position of the gate line. For pre-funded funds, unpaid subscriptions SHALL be highlighted from 2 days before their cut-off. With order journeys on, each order's status SHALL show its current journey step.

#### Scenario: Queue panel
- **WHEN** B LLP has 381.6047 units carried (queue #1) and C HUF has 978.4736 units carried (queue #2), and NAV per unit is ₹10,160.94
- **THEN** the panel shows B ≈ ₹38.77 L with a running ₹0.39 Cr, and C ≈ ₹99.42 L with a running ₹1.38 Cr

#### Scenario: Unpaid highlighted
- **WHEN** it is 24 Nov 2026, a pre-funded subscription for 1 Dec has no money received, and the cut-off is 26 Nov
- **THEN** the order is highlighted as "Awaiting money"

### Requirement: Unit register
Investors SHALL list one row per folio and class, with units, value at the latest approved NAV, cost, gain, units locked until, and units queued for redemption, plus totals. It SHALL be downloadable. Opening a row SHALL show that folio's holding, transactions, requests and documents, together with admin actions.

#### Scenario: Register totals
- **WHEN** the fund has 12 folios in class A with 99,892.3679 units and NAV per unit ₹10,160.94
- **THEN** the register total shows 99,892.3679 units and ₹101.50 Cr

### Requirement: Fees tab
Fees SHALL show:
- per class, management fee accruals by month, with NAV used, days, accrued, paid and payable;
- per class, the performance fee — high-water mark, distance of NAV per unit from it, accrued fee and crystallisation history.

When fees are not accrued up to the latest NAV date, a banner SHALL offer to run the fee formula to that date.

#### Scenario: Below the mark
- **WHEN** class A's high-water mark is ₹10,400.00 and NAV per unit is ₹10,160.94
- **THEN** Fees shows "₹239.06 below" and accrued performance fee ₹0

### Requirement: Evergreen labels
Wherever an evergreen fund's data is shown — screens, emails, documents, exports, and the settlement records underneath — the system SHALL use these labels:

| Closed-end term | Evergreen label |
|---|---|
| Capital commitment | Folio |
| Committed amount | Subscribed amount |
| Capital call | Subscription settlement |
| Remittance | Subscription payment |
| Collected | Money received |
| Distribution | Redemption settlement |
| Distribution payment | Redemption payment |
| Allocate units | Allot units |
| Redeem units | Cancel units |

Fund close, called, uncalled and call % SHALL NOT be shown. Closed-end funds SHALL keep their existing labels.

#### Scenario: Settlement record opened
- **WHEN** a fund admin follows Settlement records from the 2 Nov 2026 dealing date
- **THEN** the record is titled "Subscription settlement — 2 Nov 2026", its rows are "Subscription payments", and it links back to the dealing date

#### Scenario: Closed-end record unchanged
- **WHEN** a fund admin opens a capital call of a closed-end fund
- **THEN** it is labelled "Capital call" and shows remittances as today

### Requirement: Settlement records kept out of the way
The system SHALL NOT offer manual Allocate units or Redeem units actions on an evergreen fund's settlement records. It SHALL reach those records only from a dealing date's Settlement records link.

#### Scenario: No manual unit buttons
- **WHEN** a fund admin opens "Redemption settlement — 2 Nov 2026"
- **THEN** there is no Redeem units button, and units show as cancelled automatically when payments are marked paid

# Spec Delta

## Purpose

Gives investors in an evergreen fund pages built for evergreen investing: a landing card, Holding, Transactions, Requests, NAV history and Documents, plus guided subscribe and redeem wizards and evergreen statement fields. Closed-end commitment figures are not shown.

## ADDED Requirements

### Requirement: Landing page card
The system SHALL show an evergreen fund on the investor landing page as a card with these items, and without committed, called, uncalled or distributed figures:
- value;
- units;
- NAV per unit, with its date;
- gain since investing;
- the next dealing date and its cut-off;
- Subscribe and Redeem buttons.

#### Scenario: Card shown
- **WHEN** an investor holding 4,892.3679 class A units bought for ₹5,00,00,000 opens the landing page and the latest approved NAV per unit is ₹10,160.94 (30 Nov 2026)
- **THEN** the card shows value ₹4,97,11,057, gain −0.6 %, 4,892.3679 units × ₹10,160.94 and the next dealing date

#### Scenario: No closed-end figures
- **WHEN** an investor views an evergreen fund anywhere in the portal
- **THEN** no committed, called, uncalled, call % or distributed figure is shown

### Requirement: Evergreen fund page tabs
The system SHALL show an evergreen fund's page to investors with the tabs Holding, Transactions, Requests, NAV history and Documents:
- **Holding:** per folio and class — units, NAV per unit, value, cost, gain, units locked and until when, and units free to redeem.
- **Transactions:** each allotment and redemption, with date, units, NAV per unit, amount, fees and its contract note or redemption advice.
- **Requests:** each order with its status timeline, dealing date, queue position and carried-forward units.
- **NAV history:** approved NAV per unit over time for the investor's classes.
- **Documents:** contract notes, redemption advices and statements.

#### Scenario: Holding with lock-up
- **WHEN** an investor's 4,892.3679 units allotted on 2 Nov 2026 are in a 12-month hard lock-up
- **THEN** Holding shows "Locked: 4,892.3679 units until 2 Nov 2027 (hard lock-up)" and "Free to redeem: 0 units", and Redeem is disabled with "All your units are locked until 2 Nov 2027"

#### Scenario: No approved NAV yet
- **WHEN** an investor views a fund with no approved NAV
- **THEN** Holding shows units and cost, and "NAV not yet published" instead of value and gain

#### Scenario: Transactions with contract note
- **WHEN** an investor was allotted 4,892.3679 units on 2 Nov 2026 at ₹10,220.00
- **THEN** Transactions lists the allotment with a link to its contract note

#### Scenario: Request timeline
- **WHEN** an investor's redemption was part-filled on 2 Nov 2026 with 381.6047 units carried, and is first in the queue
- **THEN** Requests shows Received ✓, Part-filled ✓ and "Queued #1 for 1 Dec — 381.6047 units carried"

### Requirement: Subscribe wizard
The system SHALL offer Subscribe as a three-step wizard (Amount, Review, Done). The Amount step SHALL show:
- the applicable minimum;
- the dealing date and its cut-off;
- the indicative units at the latest approved NAV, labelled "Indicative — final price is the NAV for <NAV date>".

The Review step SHALL require acknowledging the offering documents. The Done step SHALL show payment instructions for a pre-funded fund, or the after-dealing message otherwise.

#### Scenario: Indicative units
- **WHEN** an investor enters ₹2,50,00,000 in class A and the latest approved NAV per unit is ₹10,160.94
- **THEN** the wizard shows indicative units ≈ 2,460.4023

### Requirement: Redeem wizard
The system SHALL offer Redeem as a wizard (What, When, Done):
- **What:** shows only the forms the fund allows, plus units held, units free to redeem, units already queued, the indicative value and any early-redemption fee.
- **When:** shows the earliest dealing date the notice period allows, the gate and the queue position the order would take.

Lock-up, notice and minimum-holding failures SHALL be shown before submission.

#### Scenario: Indicative redemption
- **WHEN** an investor holding 9,064.5793 free units enters 2,000 units with NAV per unit ₹10,160.94 and a 30-day notice period on 1 Dec 2026, and two redemptions are queued
- **THEN** the wizard shows indicative value ≈ ₹2,03,21,880, earliest dealing date 1 Jan 2027 and "you would be #3 in the queue"

#### Scenario: Redeem hidden without units
- **WHEN** an investor with access to the fund holds no units
- **THEN** Subscribe is shown and Redeem is not

### Requirement: Investors see only their own data
The system SHALL show an investor only their own folios, transactions, orders and documents, and only approved NAVs.

#### Scenario: Another investor's order
- **WHEN** an investor opens the address of another investor's order
- **THEN** access is denied

#### Scenario: Latest NAV is a draft
- **WHEN** the latest NAV for class A is a draft and the previous approved NAV is dated 30 Sep 2026
- **THEN** the investor sees NAV per unit as of 30 Sep 2026

### Requirement: Statement template fields
The system SHALL make these available to folio and investor document templates for a period, and SHALL include a sample "Evergreen quarterly statement" template:
- opening and closing units;
- opening and closing NAV per unit;
- closing holding value;
- subscriptions and redemptions in the period (units and amount);
- management and performance fees in the period;
- redemption units still queued at period end.

#### Scenario: Statement for a quarter
- **WHEN** a statement for Oct–Dec 2026 is generated for a folio allotted 4,892.3679 units on 2 Nov 2026
- **THEN** opening units are 0, closing units are 4,892.3679, and subscriptions show 4,892.3679 units / ₹5,00,00,000

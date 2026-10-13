# funds/open-ended-requests Specification

## Purpose

Captures subscription and redemption orders for evergreen funds from investors in the portal, from fund admins by entry and by upload. Each order is validated, given a dealing date, payment timing and queue position, and can be cancelled before it is dealt.

## Requirements

### Requirement: Place a subscription order
The system SHALL accept a subscription with unit class, amount and optional note:
- from an investor with access to the fund, through the portal wizard; or
- from a fund admin on the investor's behalf.

The amount SHALL be greater than zero and at least the class's minimum initial subscription, or its minimum additional subscription if the investor already holds a folio in that class.

#### Scenario: Investor subscribes before cut-off
- **WHEN** on 20 Oct 2026 an investor subscribes ₹5,00,00,000 in class A of a fund with monthly first-business-day dealing and a 5-day cut-off
- **THEN** the order is Pending with dealing date 2 Nov 2026

#### Scenario: Below minimum initial subscription
- **WHEN** a new investor subscribes ₹10,00,000 where class A's minimum initial subscription is ₹25,00,000
- **THEN** the order is rejected with "Minimum subscription is ₹25,00,000"

#### Scenario: Additional subscription minimum
- **WHEN** an investor who holds class A units subscribes ₹5,00,000 where the minimum additional subscription is ₹5,00,000
- **THEN** the order is accepted

### Requirement: Payment timing
For a fund that is paid before dealing, the system SHALL do three things when a subscription is accepted:
- open a folio for an investor who has none in that class;
- send the subscription acknowledgement with payment instructions (amount, bank account, reference, pay-by date = cut-off);
- show those instructions on the wizard's last step.

For a fund paid after dealing, the system SHALL send the acknowledgement without payment instructions, stating that instructions follow the dealing date.

#### Scenario: Pre-funded acknowledgement
- **WHEN** a new investor subscribes ₹2,50,00,000 for the 1 Dec 2026 dealing date in a pre-funded fund
- **THEN** a folio is opened, and the wizard and email show "Pay ₹2,50,00,000 by 26 Nov 2026 to be dealt on 1 Dec 2026" with the bank details and a reference

#### Scenario: Pay-after-dealing acknowledgement
- **WHEN** the same order is placed in a fund paid after dealing
- **THEN** the wizard says "You'll receive payment instructions after the 1 Dec 2026 dealing date, with the exact units" and no folio is opened yet

### Requirement: Fund currency only
The system SHALL accept orders only for folios in the fund's currency.

#### Scenario: Foreign-currency folio
- **WHEN** an order is placed for a folio in USD in a fund whose currency is INR
- **THEN** it is rejected with "Evergreen orders must be in the fund currency (INR)"

### Requirement: Assign the dealing date from cut-off and notice
The system SHALL assign each order the earliest dealing date of its type, from that type's calendar, whose cut-off (subscriptions) or notice period (redemptions, per class) the order's received time meets.

#### Scenario: Subscription after cut-off
- **WHEN** on 29 Oct 2026 an investor subscribes and the 2 Nov 2026 cut-off was 28 Oct
- **THEN** the dealing date is 1 Dec 2026 and the message says "Received after the 28 Oct cut-off — dealt on 1 Dec 2026."

#### Scenario: Redemption inside notice period
- **WHEN** on 15 Dec 2026 an investor requests a redemption in a fund with quarterly last-business-day redemptions and 30-day notice
- **THEN** the dealing date is 31 Mar 2027, because 31 Dec 2026 is inside the notice period

### Requirement: Place a redemption order
The system SHALL accept a redemption for a folio and class in exactly one of the forms the fund allows: a number of units, an amount, or all units. Units requested SHALL NOT exceed units held, minus units in a hard lock-up, minus units already queued.

#### Scenario: Redeem a number of units
- **WHEN** an investor holding 4,892.3679 free units requests to redeem 2,000 units
- **THEN** the order is Pending with a dealing date and a queue position

#### Scenario: More units than free
- **WHEN** an investor holding 4,892.3679 units, with 2,000 already queued, requests 3,000 units
- **THEN** the order is rejected with "You hold 4,892.37 units; 2,000 are already queued for redemption."

#### Scenario: Form not allowed
- **WHEN** a fund allows only Units and All units and an upload row gives an amount
- **THEN** that row is rejected with "This fund accepts redemptions in units or all units only"

### Requirement: Enforce lock-up and minimum holding
The system SHALL refuse a redemption that touches units inside a hard lock-up. It SHALL accept one inside a soft lock-up, recording the early-redemption fee that applies under the class's flat rate or age schedule. It SHALL refuse a partial redemption that would leave the folio's value below the class's minimum holding at the latest approved NAV.

#### Scenario: Hard lock-up
- **WHEN** an investor requests redemption of units of which 1,200 are inside a 12-month hard lock-up until 15 Mar 2027
- **THEN** the order is rejected with "1,200 of these units are locked until 15 Mar 2027."

#### Scenario: Soft lock-up
- **WHEN** the same order is made in a class with a soft lock-up and a 2 % fee
- **THEN** the order is accepted and shows "An early-redemption fee of 2% applies to 1,200 units."

#### Scenario: Below minimum holding
- **WHEN** a partial redemption would leave ₹40,00,000 where the minimum holding is ₹50,00,000
- **THEN** the order is rejected with "This would leave ₹40,00,000, below the ₹50,00,000 minimum holding. Redeem all units instead."

### Requirement: Queue position
The system SHALL order open redemptions for a fund by received time, then by creation order, and SHALL show each open redemption's queue position.

#### Scenario: Positions
- **WHEN** redemptions from A, B and C are received at 09:00, 10:00 and 11:00 on the same day
- **THEN** their queue positions are 1, 2 and 3

### Requirement: Cancel a pending order
The system SHALL let the investor who placed an order, or a fund admin, cancel it while it is Pending and its dealing date is not confirmed. It SHALL send the "Request cancelled" email.

#### Scenario: Cancel pending
- **WHEN** an investor cancels a Pending subscription
- **THEN** its status becomes Cancelled, it is excluded from dealing, and the cancellation email is sent

#### Scenario: Cancel after confirmation
- **WHEN** the dealing date that includes an order has been confirmed
- **THEN** no Cancel action is shown for that order

### Requirement: Admin entry and upload
The system SHALL let fund admins enter orders, and upload them with columns Type, Folio No or Investor, Unit class, Amount, Units, All units, Received at. Each row SHALL pass the same validations as a portal order, and failures SHALL be reported per row in the upload results. Admin-entered orders SHALL record the entering user and send the same investor emails.

#### Scenario: Upload with one bad row
- **WHEN** a fund admin uploads two rows where the second redeems more units than the folio holds
- **THEN** the first order is created and the second row's result says why it failed

#### Scenario: Back-dated received time
- **WHEN** a fund admin enters a redemption received at 1 Oct 2026 09:00
- **THEN** its dealing date and queue position are computed from 1 Oct 2026 09:00 and it shows "Entered by" that admin

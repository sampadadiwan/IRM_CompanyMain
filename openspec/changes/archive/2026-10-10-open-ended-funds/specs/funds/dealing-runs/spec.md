# Spec Delta

## Purpose

Runs each dealing date of an evergreen fund from one workspace. It prices ready orders at the approved NAV, applies the configured gates, settles subscriptions and redemptions through CapHive's existing settlement records, allots and cancels units automatically, and carries unfilled redemptions forward.

## ADDED Requirements

### Requirement: Dealing dates from the calendar
The system SHALL list the fund's dealing dates — generated from the subscription and redemption calendars, upcoming, open and closed — each with its cut-off, order counts and amounts, and current step.

#### Scenario: Upcoming dates shown before orders
- **WHEN** a fund with monthly first-business-day dealing has no orders for 1 Jan 2027
- **THEN** the Dealing list shows 1 Jan 2027 with cut-off 27 Dec 2026 and step "Open for orders"

### Requirement: Dealing-date step bar
Each dealing date SHALL show a step bar and a "What's needed now" panel. The steps SHALL be worked out from the dealing date's data, and the step list SHALL depend on payment timing:
- **pre-funded:** Collect subscription money, Approve NAV, Review and confirm dealing, Allot units, Pay redemptions, Cancel units, Generate documents, Approve and send documents, Close dealing date;
- **pay-after-dealing:** Approve NAV, Review and confirm dealing, Send payment instructions, Collect subscription money, Allot units, Pay redemptions, Cancel units, Generate documents, Approve and send documents, Close dealing date.

Steps with nothing to do (e.g. no redemptions) SHALL show as not applicable. Generate documents and Approve and send documents SHALL show as not applicable ("no template") when the fund has neither a contract-note nor a redemption-advice template. Generate documents SHALL be done when every settled fill whose kind has a template has a document; Approve and send documents SHALL be done when every such document is approved and sent.

#### Scenario: Pre-funded step order
- **WHEN** a pre-funded fund's 2 Nov 2026 dealing date has all subscriptions paid and an approved 31 Oct NAV, but is not yet confirmed
- **THEN** the step bar shows Collect subscription money ✓, Approve NAV ✓ and Review and confirm dealing as current

#### Scenario: No redemptions
- **WHEN** a dealing date has subscriptions only
- **THEN** Pay redemptions and Cancel units show as not applicable

#### Scenario: Document steps with templates
- **WHEN** Alpha has both templates and, on the 2 Nov 2026 dealing date, P Family Trust is allotted and A Ltd and B LLP are paid with their units cancelled
- **THEN** Allot units, Pay redemptions and Cancel units show ✓ and Generate documents is current

#### Scenario: Document steps without templates
- **WHEN** Alpha has no contract-note or redemption-advice template
- **THEN** Generate documents and Approve and send documents show as not applicable ("no template"), and Close dealing date follows Cancel units

### Requirement: Only ready orders are priced
The pricing screen SHALL include a subscription only if it is ready to deal: its order journey (if any) is at Ready to deal, and, for a pre-funded fund, it is fully paid by the cut-off. It SHALL include a redemption only if its order journey (if any) is at Ready to deal. Orders not ready SHALL be listed separately with the reason. When the dealing date is confirmed, they SHALL be rolled to the next dealing date or cancelled, per the fund setting, and the investor emailed which.

#### Scenario: Unpaid pre-funded subscription rolled
- **WHEN** a pre-funded fund set to Roll has a ₹2,50,00,000 subscription with nothing received by the 28 Oct cut-off for 2 Nov 2026
- **THEN** the order is listed as "Not paid by cut-off — will roll to 1 Dec 2026", is not priced, and after confirmation its dealing date is 1 Dec 2026

#### Scenario: Not-ready order cancelled
- **WHEN** a fund set to Cancel has a subscription whose journey is waiting on "Check investor KYC" at the cut-off
- **THEN** it is listed as "Not ready — waiting on: Check investor KYC" and is cancelled when the dealing date is confirmed

### Requirement: Preview pricing
The system SHALL show, for each dealing date until it is confirmed:
- every ready subscription, with amount, NAV per unit and units to allot;
- every ready redemption, with requested units and value, the units and amount filled, the units and amount carried forward, and its queue position;
- the gate limit, the total requested, the gate method and the fill percentage.

It SHALL recalculate on every view.

#### Scenario: Subscription units
- **WHEN** a dealing date for 2 Nov 2026 has a ready ₹5,00,00,000 class A subscription and class A's approved NAV per unit for 31 Oct 2026 is ₹10,220.00
- **THEN** the preview shows 4,892.3679 units to allot

#### Scenario: No orders
- **WHEN** a dealing date has no orders at all
- **THEN** it shows "Nothing to deal on <date>" and cannot be confirmed

#### Scenario: Only orders that are not ready
- **WHEN** a dealing date's only orders are not ready
- **THEN** it shows "Nothing to price on <date>" with each order's fate, and confirming prices nothing but rolls or cancels those orders, so none is left on a past date

#### Scenario: Not-ready order with money received
- **WHEN** an order is not ready but money has been received for it, and the fund cancels not-ready orders
- **THEN** the preview says it will roll to the next dealing date, and confirming rolls it (money received is never cancelled away); with no later dealing date it stays pending for a refund

### Requirement: Require an approved NAV
The system SHALL price each class at its approved NAV whose NAV date is the latest on or before the dealing date. Confirm SHALL be disabled while any class with ready orders lacks one.

#### Scenario: NAV not approved
- **WHEN** class A has ready orders and its 31 Oct 2026 NAV is still a draft
- **THEN** Confirm is disabled with "Approve the NAV for Class A dated 31 Oct 2026 first"

### Requirement: Apply the redemption gates
The system SHALL fill ready redemptions up to the gate, using the fund's settings:
- **Gate level:** fund-level gates compare against total fund NAV; class-level gates compare each class against its own NAV.
- **Gate period:** the gate amount is shared by every redemption dealing date in the gate period. A per-dealing-date gate resets on every dealing date.
- **Investor-level gate:** each investor's fill is first capped at the configured % of their holding for the gate period. The fund or class gate then applies.
- **Gate method:** FIFO fills in queue order until the gate is used up. Pro-rata fills every request by the same fraction, gate remaining ÷ total requested.

A 0 % gate SHALL mean no gate. Unfilled parts SHALL be carried forward.

#### Scenario: FIFO over the gate
- **WHEN** fund NAV is ₹102,20,00,000, the gate is 5 % per dealing date and FIFO, and requests in queue order are A ₹3,00,00,000, B ₹2,50,00,000, C ₹1,00,00,000
- **THEN** A is filled ₹3,00,00,000, B ₹2,11,00,000 with ₹39,00,000 carried, and C ₹0 with ₹1,00,00,000 carried

#### Scenario: Pro-rata over the gate
- **WHEN** the same requests are gated pro-rata
- **THEN** each is filled at 78.615 % of its request (5.11 ÷ 6.50) and the remainder of each is carried forward

#### Scenario: Under the gate
- **WHEN** total redemptions are ₹4,00,00,000 against a ₹5,11,00,000 gate
- **THEN** every request is filled in full

#### Scenario: Quarterly gate across monthly dealing dates
- **WHEN** the gate is 5 % of ₹100,00,00,000 per calendar quarter, ₹3,00,00,000 was paid on 1 Oct, and ₹4,00,00,000 is requested for 2 Nov
- **THEN** only ₹2,00,00,000 is filled on 2 Nov and ₹2,00,00,000 is carried forward

#### Scenario: Investor-level gate
- **WHEN** the investor-level gate is 25 % per quarter and an investor holding 4,000 units requests all units
- **THEN** at most 1,000 units are filled this quarter, before the fund gate is applied, and the rest are carried forward

#### Scenario: Class-level gate
- **WHEN** the gate is 5 % at class level, class A NAV is ₹80,00,00,000 and class B NAV is ₹20,00,00,000
- **THEN** class A redemptions are gated at ₹4,00,00,000 and class B redemptions at ₹1,00,00,000, independently

### Requirement: Confirm and settle
Confirming a dealing date SHALL store exactly what the preview showed. It SHALL settle subscriptions through one subscription settlement and redemptions through one redemption settlement for that dealing date, using CapHive's existing settlement records:
- one subscription payment per subscription, with no fees, priced at each class's approved NAV per unit;
- one redemption payment per filled redemption, carrying its filled amount, its exact units and its due date (dealing date + redemption settlement days).

Orders SHALL become Dealt, or Partially filled if carried forward. Gate notices SHALL be sent to every investor with a carried-forward amount.

#### Scenario: Confirm creates settlements
- **WHEN** a fund admin confirms the 2 Nov 2026 dealing date with one subscription and two filled redemptions
- **THEN** a "Subscription settlement — 2 Nov 2026" with one subscription payment and a "Redemption settlement — 2 Nov 2026" with two redemption payments exist, both linked to the dealing date, and the redemption payments are due on 16 Nov 2026

#### Scenario: Subscriptions only
- **WHEN** a dealing date has subscriptions but no redemptions
- **THEN** only the subscription settlement is created

### Requirement: Folio for each subscription
The system SHALL ensure each subscriber has a folio in the class before its subscription payment is created. A pre-funded fund opens it when the order is accepted; a pay-after-dealing fund opens it at confirmation. Each subscription SHALL add its amount to the folio's subscribed amount.

#### Scenario: New subscriber, pay-after-dealing
- **WHEN** a pay-after-dealing dealing date with a subscription from an investor with no folio is confirmed
- **THEN** a new class A folio with subscribed amount ₹5,00,00,000 exists and the subscription payment belongs to it

#### Scenario: Existing folio top-up
- **WHEN** a ₹1,00,00,000 subscription from folio F-012 (subscribed ₹3,00,00,000) is dealt
- **THEN** F-012's subscribed amount is ₹4,00,00,000

### Requirement: Settlement tracker
After confirmation the dealing date SHALL show one row per order, each with its status and next action inline:
- subscriptions: Awaiting money → Money received → Units allotted → (with a template: Generated → Approved →) Contract note sent;
- redemptions: Awaiting payment → Paid → Units cancelled → (with a template: Generated → Approved →) Advice sent.

The row actions are Record payment, Mark paid and Resend, plus View and Regenerate (while unapproved) for a row with a generated document. The dealing date's Actions menu SHALL offer Generate documents and Approve and send (see open-ended-documents).

#### Scenario: Mark a redemption paid
- **WHEN** a fund admin clicks Mark paid on A Ltd's ₹3,00,00,000 redemption and enters a payment date and reference, and the fund has no redemption-advice template
- **THEN** the row shows Paid, Units cancelled and Advice sent

### Requirement: Units allotted and cancelled automatically
The system SHALL allot units for a dealing date's subscription as soon as it is both confirmed and fully paid: at confirmation for pre-funded orders, and when the money is recorded for pay-after-dealing orders. It SHALL cancel exactly the dealt units when a redemption payment is marked paid. Units SHALL be dated the later of the dealing date and the payment date. Calls and distributions not created by a dealing date SHALL keep their existing manual unit buttons.

#### Scenario: Pre-funded allotment at confirmation
- **WHEN** a paid ₹5,00,00,000 subscription is confirmed on 2 Nov 2026 at ₹10,220.00
- **THEN** the folio holds 4,892.3679 new class A units dated 2 Nov 2026 and, as the fund has no contract-note template, the contract note email is sent

#### Scenario: Pay-after-dealing allotment on payment
- **WHEN** the money for a confirmed pay-after-dealing subscription is recorded on 6 Nov 2026
- **THEN** its units are allotted, dated 6 Nov 2026

#### Scenario: Redemption paid
- **WHEN** the payment for a 2,000-unit redemption is marked paid
- **THEN** exactly 2,000 units are cancelled from the folio

#### Scenario: Manual call unchanged
- **WHEN** money is recorded on a capital call not created by a dealing date
- **THEN** no units are allotted until a user clicks Allocate units, as today

### Requirement: Early-redemption fee on payment
The system SHALL deduct a redemption's early-redemption fee from its payment without changing the units cancelled.

#### Scenario: Fee deducted
- **WHEN** a ₹1,22,64,000 redemption carries a 2 % early-redemption fee on all its units
- **THEN** the net payment is ₹1,20,18,720 and the units cancelled are unchanged

### Requirement: Carry forward
The system SHALL carry the unfilled part of a partially filled redemption into the next redemption dealing date. It SHALL keep the original received time, and so the queue position, and gate it again if necessary.

#### Scenario: Carried request at the next dealing date
- **WHEN** B's ₹39,00,000 was carried from 2 Nov 2026 and a new request from D arrives on 10 Nov 2026
- **THEN** at the next redemption dealing date B is ahead of D in the queue

### Requirement: Undo a confirmed dealing date
The system SHALL allow a confirmed dealing date to be undone only while no units have been allotted or cancelled and no payment has been recorded on it. Undo SHALL remove its settlements, reverse folio top-ups made at confirmation, and return its orders to their previous status.

#### Scenario: Undo before anything settles
- **WHEN** a fund admin undoes a confirmed pay-after-dealing dealing date with no money recorded and no redemption paid
- **THEN** its settlements are gone, top-ups are reversed and orders are Pending again

#### Scenario: Undo after allotment
- **WHEN** units have been allotted on the dealing date
- **THEN** Undo is disabled with "Units allotted or payments recorded — reverse them first"

### Requirement: Close requires every document sent
Close dealing date SHALL be enabled only when every earlier applicable step is done and every settled fill has had its contract note or redemption advice emailed, whether straight away (no template) or by Approve and send (template). Otherwise Close SHALL be disabled with "Send every contract note and redemption advice first".

#### Scenario: Close requires documents sent
- **WHEN** every 2 Nov 2026 redemption is paid and every unit moved, but the generated documents are not yet approved and sent
- **THEN** Close dealing date is disabled with "Send every contract note and redemption advice first"

#### Scenario: Close after Approve and send
- **WHEN** Ravi approves and sends the 2 Nov 2026 documents
- **THEN** Close dealing date is enabled and is the current step

### Requirement: All-units redemptions resolved at confirmation
The system SHALL count an all-units redemption's units at confirmation time.

#### Scenario: Units allotted after the request
- **WHEN** an investor requested all units while holding 1,000 and was allotted 200 more before the dealing date was confirmed
- **THEN** 1,200 units are requested at confirmation (before any gate)

### Requirement: Accept the amount received for a part-paid subscription
The system SHALL allow a fund editor to accept the money received for a part-paid subscription as the whole subscription, before or after dealing, while its units are not yet allotted. The order SHALL keep its original amount, the reduced amount and who reduced it when (audited); the payment row SHALL ask only for the amount received and the folio's subscribed amount SHALL drop by the shortfall (a negative "Top Up" owned by the order). After dealing, the fill SHALL be re-sized at the same dealing NAV per unit. Units SHALL be allotted only when a subscription is paid in full or accepted at the amount received. The contract note SHALL show the amount the subscription was reduced from.

#### Scenario: Pre-funded part payment accepted before dealing
- **WHEN** ₹1,00,00,000 is ordered, ₹50,00,000 is received before the cut-off and Asha clicks Accept received amount
- **THEN** the order is for ₹50,00,000 (reduced from ₹1,00,00,000), the payment row asks for ₹50,00,000, the folio's subscribed amount is ₹50,00,000, and on confirmation units are allotted for ₹50,00,000 at the dealing NAV

#### Scenario: Pay-after part payment accepted after dealing
- **WHEN** a ₹1,00,00,000 subscription priced at ₹10,000 per unit receives ₹50,00,000 and Asha accepts it
- **THEN** the fill becomes 500 units for ₹50,00,000 and 500 units are allotted

#### Scenario: Nothing received
- **WHEN** no money has been received
- **THEN** Accept received amount is not offered and a direct request is refused with "No money has been received for this subscription — cancel it instead"


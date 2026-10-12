# Spec Delta

## Purpose

Lets an evergreen fund require each subscription, and optionally each redemption, to pass its own journey of checks before it is dealt. The journey shows its own step bar, and "Ready to deal" gates entry into the dealing date.

## ADDED Requirements

### Requirement: Order journeys per fund
When a fund's order journeys setting is Subscriptions, or Subscriptions and redemptions, the system SHALL give each new order of those types a journey from the fund's chosen template. The journey SHALL show a step bar and "What's needed now" on the order, with each step's status worked out from the order's own data. When the setting is Off, orders SHALL have no journey.

#### Scenario: Journey on subscriptions only
- **WHEN** order journeys are set to Subscriptions and an investor places a subscription and a redemption
- **THEN** the subscription has a step bar and the redemption does not

#### Scenario: Off
- **WHEN** order journeys are Off
- **THEN** no order shows a step bar and orders are ready to deal once their own validations pass

### Requirement: Seeded subscription template
The system SHALL seed an editable subscription journey template with these steps, in order:

| Step | Done when |
|---|---|
| Check investor KYC | The investor's KYC for the fund is approved |
| Collect signed subscription form | A signed subscription form is attached to the order |
| Accept order | A user with fund approve rights accepts it; rejecting asks for a reason and cancels the order |
| Collect subscription money | Payment recorded for the full amount (pre-funded only; not applicable otherwise) |
| Ready to deal | Every earlier step is done or not applicable |
| Allot units and send contract note | Units allotted |

#### Scenario: Waiting on KYC
- **WHEN** a subscription's investor KYC is pending
- **THEN** the order's current step is "Check investor KYC" and What's needed now names it

#### Scenario: Reject order
- **WHEN** a GP approver clicks Reject with reason "Investor not eligible"
- **THEN** the order is cancelled, the reason is recorded, and the Request cancelled email is sent

### Requirement: Seeded redemption template
The system SHALL seed an editable redemption journey template with the steps Verify request (authorised signatory), Accept order, Ready to deal, Pay redemption, and Cancel units and send redemption advice.

#### Scenario: Redemption verified and accepted
- **WHEN** a redemption's signatory is verified and a GP approver accepts it
- **THEN** its journey is at Ready to deal

### Requirement: Ready to deal gates the dealing date
An order with a journey SHALL be priced on a dealing date only if its journey is at Ready to deal by the cut-off. Otherwise the dealing date SHALL list it as "Not ready — waiting on: <step>". At confirmation it SHALL be rolled or cancelled per the fund setting, and a rolled redemption SHALL keep its queue position.

#### Scenario: Not ready at cut-off, rolled
- **WHEN** a subscription is waiting on "Collect signed subscription form" at the 28 Oct 2026 cut-off in a fund set to Roll
- **THEN** it is not priced on 2 Nov 2026 and its dealing date becomes 1 Dec 2026

#### Scenario: Redemption rolled keeps queue place
- **WHEN** a redemption received on 1 Oct is not ready at the cut-off and rolls, and another redemption received on 20 Oct is ready
- **THEN** at the next dealing date the 1 Oct redemption is ahead in the queue

### Requirement: Investor actions in the timeline
The system SHALL show the investor the journey steps that need them in the order's timeline, with the action (for example, an upload button for the signed subscription form).

#### Scenario: Upload signed form
- **WHEN** a subscription is at "Collect signed subscription form"
- **THEN** the investor's Requests tab shows "Upload your signed subscription form" with an Upload button, and uploading it completes the step

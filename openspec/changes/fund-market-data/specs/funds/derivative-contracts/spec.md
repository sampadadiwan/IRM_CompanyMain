# Spec Delta — Derivative Contracts

## Purpose

Lets a fund record listed and OTC derivative contracts and their events, value them from exchange
settlement prices or counterparty statements, post their ledger entries, report exposure, remind
before expiry, and carry their values into the open-ended NAV.

## ADDED Requirements

### Requirement: Derivatives are available per fund
The Derivatives screen and every derivative action SHALL be available only for a fund with the
Derivatives feature on, in an entity with the Derivatives feature on, and only to users who can
update that fund. Users of another entity SHALL never see or reach a fund's contracts.

#### Scenario: Fund without the feature
- **WHEN** a user opens a fund whose Derivatives feature is off
- **THEN** no Derivatives tab is shown and a direct request to the derivatives URL is refused

#### Scenario: Entity feature off
- **WHEN** the entity's Derivatives feature is off but a fund still has the flag set
- **THEN** the Derivatives tab is hidden and requests are refused

#### Scenario: Other entity's user
- **WHEN** a user of another entity requests a contract's URL
- **THEN** the request is refused and nothing about the contract is shown

### Requirement: Record a contract
Fund staff SHALL be able to record a contract of type option, warrant, future, forward or FX
forward, and — in the OTC swaps phase — interest-rate swap, cross-currency swap, total-return swap
or credit-default swap, with underlying (an instrument, a currency pair or an index), side (long or
short), quantity in lots and lot size or notional and its currency, strike and call/put for options,
forward rate for forwards, trade date, expiry or maturity, listed or OTC, exchange or counterparty,
and an optional agreement document. Required fields SHALL depend on the type. Recording a contract
SHALL create its trade event.

#### Scenario: Listed put recorded
- **WHEN** Meera records a long Nifty put, 1 lot × 75, strike 24,000, expiry 26 Nov 2026, premium ₹40,000 paid, on NSE
- **THEN** an open contract and its trade event are created and a ledger entry of −₹40,000 "Derivative Premium" is posted

#### Scenario: FX forward recorded
- **WHEN** Meera records a short USD→INR forward, notional USD 1,00,000 at 84.00, maturity 29 Jan 2027, counterparty Bank X
- **THEN** an open contract with no premium is created

#### Scenario: Option without strike
- **WHEN** an option is saved without a strike
- **THEN** saving is refused with "Strike can't be blank"

#### Scenario: OTC contract without counterparty
- **WHEN** an OTC contract is saved without a counterparty
- **THEN** saving is refused with "Counterparty can't be blank"

#### Scenario: Short option receives premium
- **WHEN** a short call is recorded with premium ₹30,000 received
- **THEN** a ledger entry of +₹30,000 "Derivative Premium" is posted

### Requirement: Contract events
Fund staff SHALL be able to add valuation, periodic settlement, margin or collateral, exercise,
expiry and close-out events. An event date SHALL NOT be before the trade date. No event SHALL be
added to a closed contract. Exercise and close-out SHALL NOT exceed the open lots; a partial
close-out SHALL reduce the open lots. Expiry, a full close-out, full exercise and final settlement
SHALL close the contract. A repeated submission of the same event SHALL create it once.

#### Scenario: Event before trade date
- **WHEN** a valuation dated before the trade date is entered
- **THEN** it is refused with "must be on or after the trade date"

#### Scenario: Event on a closed contract
- **WHEN** an event is added to a closed contract
- **THEN** it is refused with "Contract is closed"

#### Scenario: Partial close-out
- **WHEN** 1 of 2 open lots is closed out for ₹18,000 received
- **THEN** 1 lot stays open and the realised result on the closed lot is posted

#### Scenario: Close more lots than open
- **WHEN** a close-out of 2 lots is entered on a contract with 1 open lot
- **THEN** it is refused with "Only 1 lots open"

#### Scenario: Option expires worthless
- **WHEN** the long put expires with nothing received
- **THEN** the contract closes and the realised loss is the ₹40,000 premium

#### Scenario: Double submission
- **WHEN** the same exercise is submitted twice in quick succession
- **THEN** one exercise event and one share purchase exist

### Requirement: Contract values
A contract's value on a date SHALL be its latest valuation event on or before that date, in the
contract's currency, converted to the fund's currency with the fund's accepted FX sources. Listed
contracts SHALL be valued from the exchange settlement price in the price feed (value = settlement
price × lots × lot size, negative for a short). OTC contracts SHALL be valued from uploaded
counterparty or administrator statements. A value MAY be negative. A valuation event MAY carry a
delta.

#### Scenario: Listed contract valued from the feed
- **WHEN** the NSE F&O file gives the put a settlement price of ₹333.33 on 30 Oct
- **THEN** a Market valuation event of ₹24,999.75 is stored and the change in value (−₹15,000.25) is posted as "Derivative Unrealised Gain/Loss"

#### Scenario: Counterparty upload
- **WHEN** Meera uploads Bank X's statement valuing the forward at −₹1,50,000 on 30 Oct
- **THEN** a valuation event of −₹1,50,000 with provider "Bank X" is stored and the contract is shown as a liability

#### Scenario: Contract in a foreign currency
- **WHEN** a USD-denominated contract is valued at $2,000 for a fund that accepts Market rates, with Market USD→INR 85.00
- **THEN** its value in the fund is ₹1,70,000

### Requirement: Exercise and physical settlement
Exercising a physically settled call (or settling a long future physically) SHALL create a purchase
of the underlying of lots × lot size at the strike (or contract price) plus the premium per share;
exercising a put SHALL create a sale at the strike, using the fund's cost method, and SHALL be
refused when the fund holds fewer shares. A cash-settled exercise SHALL post a settlement entry and
create no holding.

#### Scenario: Call exercised into shares
- **WHEN** a long call on ACMEIND, 1 lot × 75, strike ₹1,000, premium ₹7,500, is exercised
- **THEN** a purchase of 75 ACMEIND at ₹1,100 per share is created and the contract closes

#### Scenario: Put exercised physically
- **WHEN** a long put on ACMEIND, 1 lot × 75, strike ₹1,300, is exercised and the fund holds 20,000 shares
- **THEN** a sale of 75 ACMEIND at ₹1,300 is created, attributed with the fund's cost method

#### Scenario: Put exercised without enough shares
- **WHEN** a physically settled put on 75 shares is exercised and the fund holds 50
- **THEN** it is refused with "Fund holds only 50 shares of ACMEIND"

#### Scenario: Cash-settled index option
- **WHEN** an index option is exercised for ₹12,000 received
- **THEN** a settlement entry of +₹12,000 is posted and no holding is created

### Requirement: OTC swaps
In the OTC swaps phase, fund staff SHALL be able to record interest-rate, cross-currency,
total-return and credit-default swaps with notional, currency, maturity, counterparty and agreement
document, and record each periodic settlement as a net amount received or paid.

#### Scenario: Interest-rate swap settlement
- **WHEN** a pay-fixed interest-rate swap on ₹10 Cr settles a quarter with ₹2,10,000 paid fixed and ₹1,95,000 received floating
- **THEN** a settlement event of −₹15,000 is stored and posted

#### Scenario: Swap without agreement
- **WHEN** a swap is saved with no agreement document
- **THEN** saving is refused with "Agreement can't be blank"

### Requirement: Hedge link
A contract SHALL optionally record the holding or the share class (unit type) it hedges, and the
hedged holding SHALL show the contract and its value.

#### Scenario: Forward hedges a holding
- **WHEN** the FX forward is marked as hedging Nimbus Inc
- **THEN** Nimbus Inc's holding shows "Hedged by: FX forward, sell USD 1,00,000 @ 84.00 (−₹1,50,000)"

#### Scenario: Contract hedges a share class
- **WHEN** a contract is marked as hedging unit type "Class B"
- **THEN** the contract shows "Hedges: Class B"

### Requirement: Exposure measure
Each fund with Derivatives SHALL measure exposure by one method: Gross (sum of each open contract's
notional in the fund's currency; options delta-adjusted when a delta is known, otherwise full
notional labelled "full notional"; short puts at strike × quantity when no delta) or Commitment
(Gross, minus hedge-linked contracts up to the value they cover, minus opposite positions on the
same underlying and expiry). Commitment SHALL be the default. The exposure report SHALL show each
contract's gross and counted exposure and the total.

#### Scenario: Commitment nets a hedge
- **WHEN** Horizon (Commitment) holds the FX forward on USD 1,00,000 at 85.00, linked to Nimbus Inc worth ₹1,02,00,000
- **THEN** the forward shows gross ₹85,00,000 and counted ₹0

#### Scenario: Commitment nets opposite positions
- **WHEN** a fund holds a long and a short Nifty future of 1 lot × 75 each, same expiry, at 24,500
- **THEN** gross is ₹36,75,000 and counted is ₹0

#### Scenario: Exposure with and without delta
- **WHEN** an option has delta −0.30 on a 75-lot over an underlying at 24,500, and another option has no delta
- **THEN** the first counts ₹5,51,250 and the second counts its full notional labelled "full notional"

#### Scenario: Short put without delta
- **WHEN** a short put of 1 lot × 75 at strike ₹1,000 has no delta
- **THEN** it counts ₹75,000

### Requirement: Limit profiles
Each fund with Derivatives SHALL have a limit profile: SEBI Cat I/II AIF (hedging only, no
leverage), SEBI Cat III AIF (leverage ≤ 2× NAV, Commitment), UCITS-style (Commitment exposure ≤
100 % of NAV; OTC counterparty ≤ 10 % of NAV for banks, 5 % for others), US '40 Act limited user
(exposure ≤ 10 % of net assets, excluding currency and interest-rate hedges), or Custom. Choosing a
preset SHALL fill its limits; changing any of them SHALL label the profile "(customised)". Every
limit SHALL be optional (blank = off). Fund staff SHALL also be able to set a counterparty
concentration limit, a single-underlying limit (holdings plus derivatives on one name, as % of NAV),
and whether naked short calls are allowed (default: not allowed).

#### Scenario: Cat III preset
- **WHEN** fund staff choose the SEBI Cat III AIF preset for Horizon
- **THEN** the method is Commitment, the leverage limit 2.0× and naked short calls not allowed

#### Scenario: Preset customised
- **WHEN** fund staff change the leverage limit of a Cat III profile to 1.5×
- **THEN** the profile shows "SEBI Cat III AIF (customised)"

#### Scenario: '40 Act preset excludes hedges
- **WHEN** Horizon uses the US '40 Act preset and holds the put and the FX forward hedge
- **THEN** only the put counts towards exposure

### Requirement: Hard derivative rules
A fund with the hedging-only rule (SEBI Cat I/II preset) SHALL refuse a contract with no hedge link
with "This fund allows hedging contracts only — link the holding or class it hedges", and SHALL
refuse a hedge whose notional exceeds the value it covers with "Hedge exceeds the value it covers
({hedge} > {covered})". Unless naked short calls are allowed, a short call SHALL be refused when the
fund holds fewer shares than it covers, with "Writing this call needs {n} shares of {instrument};
the fund holds {m}".

#### Scenario: Hedging-only fund, no hedge link
- **WHEN** a fund on the SEBI Cat I/II preset records a Nifty put with no hedge link
- **THEN** it is refused with "This fund allows hedging contracts only — link the holding or class it hedges"

#### Scenario: Hedge larger than what it covers
- **WHEN** that fund records an FX forward on USD 1,00,000 (₹85,00,000) hedging a holding worth ₹50,00,000
- **THEN** it is refused with "Hedge exceeds the value it covers (₹85,00,000 > ₹50,00,000)"

#### Scenario: Naked short call
- **WHEN** a fund that holds no Rangoli Textiles shares records a short call on 1 lot × 500
- **THEN** it is refused with "Writing this call needs 500 shares of Rangoli Textiles; the fund holds 0"

#### Scenario: Naked short calls allowed
- **WHEN** the fund allows naked short calls and records the same short call
- **THEN** the contract is recorded

### Requirement: Limit checks against NAV
Percentage-of-NAV limits (leverage, counterparty, single underlying, '40 Act) SHALL be checked
against the latest approved NAV, and so only for open-ended funds; for other funds the exposure
report SHALL show amounts and the hard rules only, with the percentage rows marked "Checked on
open-ended funds". A value at or above 90 % of a limit SHALL show amber; a value above the limit SHALL
show red (exactly at the limit is amber). Counterparty exposure SHALL count only positive OTC values
(what the counterparty owes the fund). A red limit SHALL add an exception to the NAV draft and
email Compliance-tagged users and NAV approvers once per fund, limit and date. Recording a contract
that would take a limit red SHALL show a confirmation with the before and after figures, and SHALL
record the contract once confirmed.

#### Scenario: Within limits
- **WHEN** Horizon's counted exposure is ₹18,00,000 against a NAV of ₹4,33,75,000 and a 2.0× limit
- **THEN** the report shows 0.04× in green and no exception

#### Scenario: Amber near the limit
- **WHEN** counted exposure is ₹7,90,00,000 against a NAV of ₹4,33,75,000 and a 2.0× limit
- **THEN** the report shows 1.82× in amber

#### Scenario: Exactly at the limit
- **WHEN** counted exposure is ₹8,67,50,000 against a NAV of ₹4,33,75,000 and a 2.0× limit
- **THEN** the report shows 2.00× in amber, not red

#### Scenario: Exposure against NAV limit
- **WHEN** an open-ended fund's counted exposure is ₹9,00,00,000, its latest approved NAV ₹4,33,75,000 and its limit 2×
- **THEN** the report shows 2.07× in red against the 2.0× limit, the NAV draft lists it as an exception, and Compliance and approvers are emailed

#### Scenario: Bank counterparty over its limit
- **WHEN** Bank X (a bank) owes the fund ₹50,00,000 on OTC contracts and the bank limit is 10 % of a ₹4,33,75,000 NAV
- **THEN** Bank X shows 11.5 % in red

#### Scenario: Negative value is not counterparty exposure
- **WHEN** the fund owes Bank X ₹1,50,000 on the forward
- **THEN** Bank X's counterparty exposure is 0 %

#### Scenario: Non-bank counterparty over its limit
- **WHEN** a non-bank counterparty owes the fund ₹26,00,000 and the non-bank limit is 5 % of a ₹4,33,75,000 NAV
- **THEN** it shows 6.0 % in red

#### Scenario: Single underlying over its limit
- **WHEN** ACMEIND holdings are ₹2,50,00,000 and a long ACMEIND call counts ₹46,875, with a 50 % single-underlying limit and a NAV of ₹4,33,75,000
- **THEN** ACMEIND shows 57.7 % in red

#### Scenario: Breach emailed once
- **WHEN** the same leverage breach is found by two drafts on the same date
- **THEN** one email is sent

#### Scenario: Contract that would breach
- **WHEN** Meera records a future that would take leverage from 1.95× to 2.10×
- **THEN** a confirmation shows "Leverage 1.95× → 2.10× (limit 2.0×)" and the contract is recorded once she confirms

#### Scenario: Closed-ended fund
- **WHEN** a fund that is not open-ended has Derivatives and a leverage limit
- **THEN** the exposure report shows amounts and the hard rules, and the percentage rows read "Checked on open-ended funds"

### Requirement: Expiry reminder
The system SHALL email the fund's Fund accounting users once, 5 business days before an open
contract's expiry or maturity.

#### Scenario: Reminder sent once
- **WHEN** the reminder job runs on two days within the window for the put expiring 26 Nov
- **THEN** one reminder is sent, on 19 Nov

### Requirement: Open-ended NAV derivative lines
An open-ended fund's NAV SHALL include Derivative assets (sum of positive contract values) and
Derivative liabilities (sum of negative contract values) on the NAV date for open contracts. A
contract valued exactly zero SHALL add to neither. An open contract with no valuation on or before
the NAV date SHALL block the draft. A derivative valuation added or changed on or before the NAV
date SHALL mark the NAV "Inputs changed". A fund with no contracts SHALL get the same NAV as before
this change.

#### Scenario: NAV with derivative lines
- **WHEN** Horizon drafts its 30 Oct NAV with the put at ₹25,000 and the forward at −₹1,50,000
- **THEN** Derivative assets is ₹25,000, Derivative liabilities is ₹1,50,000, and NAV is ₹4,33,75,000 (₹108.44 per unit)

#### Scenario: Missing derivative value blocks the draft
- **WHEN** an open contract has no valuation on or before the NAV date
- **THEN** the draft is refused with "No valuation for {contract} on or before {date}"

#### Scenario: Zero value
- **WHEN** an open contract is valued at exactly zero
- **THEN** it adds to neither line

#### Scenario: Valuation upload marks the NAV
- **WHEN** a counterparty valuation dated on or before the NAV date is uploaded after the draft
- **THEN** the NAV shows "Inputs changed"

#### Scenario: Fund without contracts
- **WHEN** an open-ended fund with no contracts drafts a NAV
- **THEN** both derivative lines are zero and every other figure is as before this change

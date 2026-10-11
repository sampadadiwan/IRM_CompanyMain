# Spec Delta — Market Prices

## Purpose

Prices listed holdings from daily exchange and fund-NAV files, lets each fund choose whether it
uses those prices, keeps purchases from overwriting prices, suggests corporate actions, and adds
price checks to the open-ended NAV draft.

## ADDED Requirements

### Requirement: Instrument identifiers and pricing method
Each investment instrument SHALL have an ISIN, ticker, exchange and pricing method (Market, Model,
Manual or Cost). Existing instruments SHALL become Manual, and an ISIN held in the SEBI custom field
SHALL be copied into the ISIN field. Market SHALL require a ticker and exchange, or an ISIN, and SHALL be allowed only on exchanges a selected price feed covers.

#### Scenario: Existing instruments become Manual
- **WHEN** the change is deployed
- **THEN** every existing instrument shows Pricing method Manual and keeps its fair values, and an ISIN in the SEBI field appears in the ISIN field

#### Scenario: Instrument set to Market
- **WHEN** Meera sets ACMEIND to ticker ACMEIND, exchange NSE, Pricing method Market
- **THEN** the instrument shows a Market badge

#### Scenario: Invalid ISIN
- **WHEN** an ISIN with a wrong check digit is entered
- **THEN** saving is refused with "ISIN is not valid"

#### Scenario: Market without identifiers
- **WHEN** Pricing method Market is chosen with no ticker, exchange or ISIN
- **THEN** saving is refused with "Market pricing needs a ticker and exchange, or an ISIN"

#### Scenario: Exchange not covered by a feed
- **WHEN** Pricing method Market is chosen for a NASDAQ instrument
- **THEN** saving is refused with "No price feed covers NASDAQ; keep this holding Manual"

#### Scenario: Duplicate ticker
- **WHEN** a ticker and exchange already used by another instrument of the entity is entered
- **THEN** saving is refused with "Ticker already used by {instrument}"

#### Scenario: Switching to Market keeps history
- **WHEN** an instrument with Manual valuations is switched to Market
- **THEN** its Manual valuations are kept and Market valuations are added from the next run

### Requirement: Every price records its source
Every valuation SHALL record a source (Manual, Market or Cost), a provider and a price type (Close,
Bid or Mid). Valuations existing before this change SHALL become Manual. At most one valuation SHALL
exist per instrument, owner, date and source.

#### Scenario: Existing valuations become Manual
- **WHEN** the change is deployed
- **THEN** every existing valuation shows Source Manual and fair values are unchanged

#### Scenario: Valuation upload with Price Type
- **WHEN** a valuation upload sets Price Type to Mid
- **THEN** the stored valuation has price type Mid and source Manual

#### Scenario: Duplicate manual valuation
- **WHEN** a second Manual valuation is added for the same instrument and date
- **THEN** it is refused with the existing duplicate message

### Requirement: A fund uses only the price sources it accepts
A fund's fair value for a holding SHALL use the most recent valuation on or before the date among
the sources it accepts (Manual and Cost always; Market when the fund accepts market prices). On the
same date Manual SHALL win over Market, and Market over Cost.

#### Scenario: Two funds price the same holding differently
- **WHEN** ACMEIND has a Manual valuation ₹1,100 (30 Sep) and a Market ₹1,250 (30 Oct), and Bridge Hybrid accepts market prices while Growth AIF II does not
- **THEN** on 30 Oct Bridge Hybrid uses ₹1,250 and Growth AIF II ₹1,100

#### Scenario: Manual beats Market on the same date
- **WHEN** a Manual ₹1,240 and a Market ₹1,250 exist for ACMEIND on 30 Oct
- **THEN** a fund accepting market prices uses ₹1,240

#### Scenario: Market beats Cost on the same date
- **WHEN** a purchase on 30 Oct records a Cost price ₹1,230 and the Market close is ₹1,250
- **THEN** a fund accepting market prices uses ₹1,250

#### Scenario: Manual-only fund uses Cost
- **WHEN** a Manual-only fund buys a holding with no Manual valuation
- **THEN** the purchase's Cost price is its fair value

### Requirement: Purchases never overwrite prices
A purchase SHALL record a Cost valuation for its date and SHALL NOT replace a Manual or Market
valuation for that date.

#### Scenario: Purchase on a day with a market close
- **WHEN** Horizon buys ACMEIND on 30 Oct at ₹1,230 and the Market close for 30 Oct is ₹1,250
- **THEN** the Market ₹1,250 valuation is unchanged and a Cost ₹1,230 valuation is added

### Requirement: Daily price feed
For an entity with Market prices on and the price feed switched on, the system SHALL fetch, every
business day after each market closes, the closing price of every Market instrument from the
selected providers (NSE and BSE by ticker, AMFI by ISIN; holdings on other exchanges stay manually priced until a vendor is added for a client)
and store it as a Market valuation of that entity only — market prices are never shared between entities. A re-run for the same date SHALL update rather than duplicate.
Each holding affected by a run SHALL be recomputed once per run. A weekday run that loads nothing,
or misses some instruments, SHALL email the entity's Fund accounting users once, naming each
missing instrument and the reason.

#### Scenario: Feed loads prices
- **WHEN** the price feed runs for 30 Oct and NSE reports ACMEIND at ₹1,250
- **THEN** a Market valuation ₹1,250, provider NSE, price type Close, dated 30 Oct is stored

#### Scenario: Mutual fund matched by ISIN
- **WHEN** a Market instrument has only an ISIN and AMFI reports its NAV
- **THEN** the AMFI NAV is stored as its Market valuation

#### Scenario: One recompute per holding per run
- **WHEN** a run stores prices for several instruments of one portfolio company
- **THEN** each affected holding is recomputed once

#### Scenario: Re-run is idempotent
- **WHEN** the price feed runs twice for 30 Oct
- **THEN** one Market valuation per instrument exists for 30 Oct

#### Scenario: Ticker not found
- **WHEN** NSE does not recognise Rangoli Textiles' ticker
- **THEN** the other prices are stored and Fund accounting receives "Price feed: no prices loaded for {date}" naming "Rangoli Textiles — ticker not found at NSE"

#### Scenario: Test feed
- **WHEN** the entity admin clicks Test feed
- **THEN** a popup lists every Market instrument and listed contract and whether each was found, without storing anything

### Requirement: Corporate-action suggestions
For an entity with Market prices on, the system SHALL record splits and dividends reported by the
price providers for Market instruments as suggestions. A person SHALL confirm a suggestion into the
existing stock adjustment or income record, or dismiss it. The same corporate action SHALL never be
suggested twice, whether pending, confirmed or dismissed. Fund accounting SHALL be emailed once per
new suggestion.

#### Scenario: Split confirmed
- **WHEN** NSE reports a 1:2 split for ACMEIND and Meera confirms the suggestion
- **THEN** a stock adjustment is created as if entered by hand, doubling quantities and halving prices

#### Scenario: Suggestion dismissed
- **WHEN** Meera dismisses a suggested dividend
- **THEN** nothing changes and the dividend is not suggested again by later runs

#### Scenario: Reported again
- **WHEN** a later run reports a corporate action that is already suggested
- **THEN** no new suggestion and no new email are created

### Requirement: Open-ended NAV price checks
For an open-ended fund's NAV draft, the system SHALL list as exceptions every Market-priced holding
whose price moved more than the fund's threshold since its previous valuation (a move exactly equal
to the threshold is not an exception), and every Market-priced holding or listed contract whose
price is older than the fund's maximum price age. A missing price SHALL block the draft. Manual and
Model marks SHALL show their date and age but SHALL NOT be exceptions. Approve SHALL be disabled,
and refused if requested directly, while any exception is open. Only a NAV approver SHALL accept an
exception, with a note. A redraft SHALL keep an acceptance when the item and its value are
unchanged, and SHALL reopen it when the value changed.

#### Scenario: Move above threshold
- **WHEN** ACMEIND moved from ₹1,020 to ₹1,250 (+22.5 %) and the threshold is 10 %
- **THEN** the draft lists "ACMEIND moved +22.5% (₹1,020 → ₹1,250); threshold 10%"

#### Scenario: Move exactly at threshold
- **WHEN** a price moved exactly 10.00 % and the threshold is 10 %
- **THEN** no exception is raised

#### Scenario: Stale market price
- **WHEN** a Market price is older than the fund's maximum price age
- **THEN** the draft lists it as stale

#### Scenario: Private mark shows age
- **WHEN** Private Co A's Manual mark is dated 30 Sep for a 30 Oct NAV
- **THEN** the line shows "Manual · 30 Sep (30d)" and no exception

#### Scenario: Missing price blocks the draft
- **WHEN** a Market holding has no accepted price on or before the NAV date
- **THEN** the draft is refused with "No price for {instrument} on or before {date}"

#### Scenario: Approver accepts an exception
- **WHEN** Arjun accepts the ACMEIND exception with a note
- **THEN** the exception shows "Accepted by Arjun" with the time and note

#### Scenario: Approve with an open exception
- **WHEN** an approve request is sent while an exception is open
- **THEN** it is refused with "Resolve or accept every exception first"

#### Scenario: Non-approver cannot accept
- **WHEN** a fund user who is not a NAV approver tries to accept an exception
- **THEN** the request is refused

#### Scenario: Redraft keeps unchanged acceptance
- **WHEN** a NAV is redrafted and the accepted item's value is unchanged
- **THEN** the exception stays accepted

#### Scenario: Redraft reopens changed item
- **WHEN** a NAV is redrafted and the accepted item's value changed
- **THEN** the exception is open again

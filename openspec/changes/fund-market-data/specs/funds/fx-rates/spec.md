# Spec Delta — FX Rates

## Purpose

Gives each fund FX rates from the sources it has chosen — manual, market feed, or derived — with
the source of every rate recorded, a daily feed, reverse and cross rates, a price/currency split of
gains, and open-ended NAV checks on rate age and rate changes.

## ADDED Requirements

### Requirement: Every rate records its source
Every exchange rate SHALL record a source (Manual, Market or Derived), a provider (for example
"User", "Upload", "ECB via EUR", "ECB", "via USD", "reverse") and a rate type (Reference or Closing). Rates
existing before this change SHALL become Manual, with provider "Upload" when they came from an
upload and "User" otherwise. At most one rate SHALL exist per entity, pair, date and source.

#### Scenario: Existing rates become Manual
- **WHEN** the change is deployed on an entity with existing rates
- **THEN** every existing rate shows Source Manual, and every converted amount and fair value is unchanged

#### Scenario: Manual and Market rate on the same date
- **WHEN** a Manual and a Market USD→INR rate exist for 30 Oct 2026
- **THEN** both are stored and listed, each with its source

#### Scenario: Duplicate manual rate
- **WHEN** a second Manual USD→INR rate is added for a date that already has one
- **THEN** it is refused with the existing duplicate-rate message

#### Scenario: Upload without a Source column
- **WHEN** an exchange-rate upload has no Source column
- **THEN** its rows are stored as Manual with provider "Upload"

### Requirement: A fund uses only the rate sources it accepts
Every currency conversion made for a fund SHALL use the most recent rate on or before the
conversion date among the sources the fund accepts (Manual always; Market and Derived when the
fund's features say so). On the same date a Manual rate SHALL win over a Market rate, and a direct
rate SHALL win over a derived one. Conversions made outside any fund (entity-level reports,
portfolio-company KPIs) SHALL use the entity's default sources. The rate used SHALL be recorded on
the converted record as today.

#### Scenario: Two funds value the same holding with different rates
- **WHEN** Growth AIF II (Manual only) and Horizon Evergreen Fund (Manual + Market) both hold Nimbus Inc on 30 Oct 2026, with USD→INR Manual 83.00 dated 1 Apr and Market 85.00 dated 30 Oct
- **THEN** Growth AIF II values it at 83.00 and Horizon at 85.00

#### Scenario: Manual wins on the same date
- **WHEN** a fund accepts Market and both a Manual 84.80 and a Market 85.00 USD→INR rate exist for 30 Oct
- **THEN** the fund uses 84.80

#### Scenario: Newer market rate beats older manual rate
- **WHEN** a fund accepts Market, a Manual rate is dated 26 Oct and a Market rate 30 Oct
- **THEN** a 30 Oct conversion uses the Market rate

#### Scenario: Manual-only fund ignores newer market rate
- **WHEN** a Manual-only fund converts on 30 Oct and a Market rate exists for 30 Oct but the latest Manual rate is 1 Apr
- **THEN** the 1 Apr Manual rate is used

#### Scenario: No accepted rate
- **WHEN** a Manual-only fund books a EUR purchase and no Manual EUR→INR rate exists on or before the date
- **THEN** the save is refused with "No EUR→INR rate on or before {date} in this fund's accepted sources (Manual). Enter a manual rate, or accept derived rates for this fund."

#### Scenario: Same currency
- **WHEN** the from and to currencies are the same
- **THEN** the rate is 1 and no lookup is made

#### Scenario: Entity-level conversion uses entity defaults
- **WHEN** a portfolio-company KPI is converted and the entity default is Manual only
- **THEN** only Manual rates are considered

#### Scenario: Allocation run resolves the same rate
- **WHEN** an allocation run converts an amount for a fund
- **THEN** it uses the same rate the live screens use for that fund and date

### Requirement: Derived rates
For a fund that accepts Derived rates, when building a rate the system SHALL consider the reverse
of a direct rate (1 ÷ rate) and the cross through the entity's pivot currency (from→pivot ×
pivot→to), each built only from direct rates in the fund's other accepted sources. Among direct,
reverse and cross candidates the most recent SHALL win, with ties resolved direct, then reverse,
then cross. A derived rate's date SHALL be the older of its legs. A derived rate SHALL be stored as
a Derived rate with provider "reverse" or "via {pivot}" and links to its legs, and SHALL be rebuilt
when a leg changes. Storing a derived rate SHALL NOT start the portfolio recompute or the
commitment adjustment.

#### Scenario: Cross rate from manual legs
- **WHEN** Bridge Hybrid Fund (Manual + Derived) needs EUR→INR on 30 Oct, with Manual EUR→USD 1.07 (30 Sep) and Manual USD→INR 83.00 (1 Apr)
- **THEN** it uses 88.81, shown as Derived (via USD), dated 1 Apr

#### Scenario: Reverse rate
- **WHEN** a fund accepting Derived needs GBP→INR and only a Manual INR→GBP 0.0095 exists
- **THEN** it uses 105.26315789, shown as Derived (reverse)

#### Scenario: Legs limited to accepted sources
- **WHEN** Bridge Hybrid (no Market) needs EUR→INR and EUR→USD exists only as Market
- **THEN** no cross is built from it and the conversion is refused if no other accepted rate exists

#### Scenario: Newer derived beats older direct
- **WHEN** a fund accepting Derived has a direct Manual EUR→INR dated 1 Jan and a cross whose older leg is 30 Sep
- **THEN** the cross rate is used

#### Scenario: Leg corrected
- **WHEN** a leg of a stored derived rate is replaced by a new Manual rate for the same date
- **THEN** the derived rate is rebuilt from the new leg on the next conversion

#### Scenario: Derived rate starts no jobs
- **WHEN** a derived rate is stored
- **THEN** no portfolio recompute and no commitment adjustment is started

### Requirement: Fund-specific FX rates
A rate SHALL be entity-wide by default. A Manual rate MAY instead belong to one fund that has the
"Use fund-specific FX rates" feature on. A fund's own rates SHALL be considered only for that fund's
conversions, and only while the feature is on; other funds and entity-level conversions SHALL never
use them. Among a fund's candidates the most recent rate on or before the date SHALL win; on the
same date the fund's own rate SHALL win over an entity Manual rate. A derived rate for the fund MAY
use the fund's own rates as legs. A new own rate SHALL recompute fair values and run the
exchange-rate commitment adjustment only for its fund. The feed SHALL never write fund-specific
rates.

#### Scenario: Fund-specific rate used only by its fund
- **WHEN** Horizon has the feature on and its own USD→INR 84.50 dated 30 Oct exists
- **THEN** Horizon converts at 84.50 while Bridge Hybrid Fund, Growth AIF II and entity reports use their own sources

#### Scenario: Fund rate beats entity rate on the same date
- **WHEN** Horizon's own 84.50 and an entity Manual 84.80 are both dated 30 Oct
- **THEN** Horizon uses 84.50

#### Scenario: Newer entity rate beats older fund rate
- **WHEN** Horizon's own rate is dated 26 Oct and an accepted entity rate is dated 30 Oct
- **THEN** Horizon uses the 30 Oct entity rate

#### Scenario: Own rates ignored when the feature is off
- **WHEN** Horizon turns the feature off while its own rates exist
- **THEN** the own rates are kept and listed but not used

#### Scenario: Derived rate from a fund's own leg
- **WHEN** Horizon accepts Derived, has its own USD→INR 84.50 and a Market EUR→USD 1.08, both 30 Oct, and no EUR→INR
- **THEN** Horizon's EUR→INR is 91.26, Derived (via USD), belonging to Horizon

#### Scenario: Own rate affects only its fund
- **WHEN** an own Manual rate is added for Horizon in an entity with the commitment adjustment option on
- **THEN** only Horizon's commitments are adjusted and only Horizon's fair values are recomputed

#### Scenario: Own rate for a fund without the feature
- **WHEN** an exchange-rate upload row names a fund that does not have the feature, or a fund of another entity
- **THEN** the row is refused with "Fund {name} does not use fund-specific FX rates" or "Fund {name} not found"

### Requirement: Daily FX rate feed
For an entity with Market FX rates on and the FX feed switched on, the system SHALL fetch, every
business day after the providers publish, closing or reference rates for each currency pair in use
(fund currencies, holding currencies, investor folio currencies and derivative currencies of the
entity) and store them as Market rates of that entity only — market rates are never shared between entities. A re-run for the same date SHALL update rather than
duplicate. Weekends SHALL be skipped. A weekday run that loads nothing, or misses some pairs, SHALL
email the entity's Fund accounting users once, listing the missing pairs.

#### Scenario: Feed loads rates
- **WHEN** the FX feed runs for 30 Oct 2026 and the ECB table gives USD→INR 85.00 (through EUR)
- **THEN** a Market USD→INR 85.00 rate, provider "ECB via EUR", type Reference, dated 30 Oct is stored

#### Scenario: Market rates stay in their entity
- **WHEN** two entities run the FX feed for 30 Oct with different providers
- **THEN** each stores its own Market rows, and neither entity's conversions or screens use the other's

#### Scenario: Re-run is idempotent
- **WHEN** the feed runs twice for 30 Oct
- **THEN** one Market rate per pair exists for 30 Oct

#### Scenario: New pair tracked
- **WHEN** a fund in GBP is added
- **THEN** the next run also fetches the GBP pair

#### Scenario: Weekend skipped
- **WHEN** the feed is due on a Saturday
- **THEN** no fetch is attempted and no email is sent

#### Scenario: Provider down
- **WHEN** the provider fails on a weekday after retries
- **THEN** Fund accounting receives "FX feed: no rates loaded for {date}" listing the pairs, once

#### Scenario: Some pairs missing
- **WHEN** the run loads USD→INR but the provider publishes no AED rate
- **THEN** USD→INR is stored and the email lists only AED→INR

#### Scenario: Invalid rate from provider
- **WHEN** the provider returns a rate of zero or less for a pair
- **THEN** that pair is not stored and is listed as missing

### Requirement: Correcting a rate
A rate SHALL be corrected by adding a Manual rate for the same pair and date; the Market rate SHALL
remain as history, and the Manual rate SHALL be used by every fund from then on.

#### Scenario: Manual correction of a fed rate
- **WHEN** Meera adds a Manual USD→INR 84.80 for 30 Oct where a Market 85.00 exists
- **THEN** both are listed, and funds accepting Market now use 84.80 for 30 Oct

### Requirement: Rate changes and dependent work
A new Market or Manual rate SHALL recompute the current fair values only of funds whose accepted
sources include that rate's source. The exchange-rate commitment adjustment SHALL react only to
Manual rates. Booked commitments, calls, remittances and distributions SHALL keep the rate recorded
when they were booked. Changing a fund's accepted sources SHALL recompute that fund's current fair
values and leave booked amounts unchanged.

#### Scenario: Market rate recomputes only accepting funds
- **WHEN** a Market USD→INR rate arrives
- **THEN** Horizon's holdings are recomputed and Growth AIF II's are not

#### Scenario: Fed rate creates no commitment adjustment
- **WHEN** a Market rate arrives in an entity with the exchange-rate commitment adjustment option on
- **THEN** no commitment adjustment is created

#### Scenario: Changing accepted sources
- **WHEN** fund staff turn on Accept market FX rates for a fund
- **THEN** the fund's fair values are recomputed, its booked commitments and calls keep their amounts, and the audit trail records the change

### Requirement: Gain split into price and currency
For a holding in a currency other than the fund's, the system SHALL show unrealised and realised
gain split into price effect (change in local price × quantity, at the current rate) and currency
effect (local cost × change in rate), and the two SHALL add up exactly to the total gain.

#### Scenario: Unrealised split
- **WHEN** Horizon holds 1,000 Nimbus Inc bought at $100 at 83.00, valued at $120 at 85.00
- **THEN** the holding shows gain ₹19,00,000 = price effect ₹17,00,000 + currency effect ₹2,00,000

#### Scenario: Split adds up after rounding
- **WHEN** the price and currency effects do not each come out to whole paise
- **THEN** the currency effect is the total gain minus the rounded price effect, so they add up exactly

#### Scenario: Realised split on a sale
- **WHEN** a holding is sold
- **THEN** the realised gain is split the same way, using the cost rate of the lots sold

### Requirement: Open-ended NAV rate checks
For an open-ended fund's NAV, every rate used SHALL be no older than the fund's maximum rate age in
business days (Monday–Friday) before the NAV date; an older rate SHALL be listed as an exception the
approver accepts or fixes, and a missing rate SHALL block the draft. Adding or changing any rate of
the entity on or before the NAV date SHALL mark the NAV "Inputs changed". An approved NAV SHALL
never be rebuilt automatically.

#### Scenario: Rate at the age limit
- **WHEN** the NAV date is Fri 30 Oct, the limit is 3 business days and the rate is dated Tue 27 Oct
- **THEN** no exception is raised

#### Scenario: Rate older than the limit
- **WHEN** the latest accepted rate is dated Mon 26 Oct for a Fri 30 Oct NAV with a 3-day limit
- **THEN** the draft lists the rate as an exception to accept or fix

#### Scenario: Missing rate blocks the draft
- **WHEN** no accepted USD→INR rate exists on or before the NAV date
- **THEN** the draft is refused with "No USD→INR rate within 3 business days of {date} (latest: {date}). Enter a manual rate or wait for the feed."

#### Scenario: Rate change marks the NAV
- **WHEN** a Manual USD→INR rate for 30 Oct is added after the 30 Oct NAV was drafted
- **THEN** the NAV shows "Inputs changed"

#### Scenario: Approved NAV not rebuilt
- **WHEN** a rate changes after a NAV was approved
- **THEN** the NAV keeps its figures and shows "Inputs changed"

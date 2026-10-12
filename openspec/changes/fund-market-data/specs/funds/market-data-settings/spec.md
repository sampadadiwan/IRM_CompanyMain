# Spec Delta — Market Data Settings and Fund Features

## Purpose

Lets CapHive switch market-data features on for an entity and lets each fund choose which of them
it uses, through one fund feature set that also holds the fund's existing investor-visibility and
reporting switches.

## ADDED Requirements

### Requirement: Entity market-data features
The system SHALL provide three entity features — Market FX rates, Market prices and Derivatives —
that only CapHive support can switch on or off, alongside the entity's existing features. With
none of them on, the system SHALL show no market-data screens, settings or fund switches for that
entity.

#### Scenario: Support switches on the entity features
- **WHEN** CapHive support ticks Market FX rates, Market prices and Derivatives on an entity and saves
- **THEN** the entity shows the three features as on and its admins see the Market Data settings card

#### Scenario: Entity with no market-data feature
- **WHEN** an entity has none of the three features on
- **THEN** no Market Data card, fund market-data switch, Derivatives tab or Corporate actions tab is shown, and every converted amount and fair value is the same as before this change

#### Scenario: Non-support user cannot switch entity features
- **WHEN** an entity admin who is not CapHive support submits a change to the entity features
- **THEN** the change is refused and the features are unchanged

### Requirement: Entity Market Data settings
The system SHALL let an entity admin set, for the entity: whether the FX rate feed runs and which
providers it uses, whether the price feed runs and which providers it uses (only the free public
sources in this change — ECB, NSE, BSE, AMFI, NSE F&O; licensed vendors are added later per
client), the cross-rate pivot currency (default USD), and the defaults a new fund starts with (accepted sources, maximum rate age, maximum price age,
price-move threshold).

#### Scenario: Admin sets feeds and defaults
- **WHEN** the entity admin turns on the FX feed (ECB) and the price feed (NSE, BSE, AMFI), sets pivot USD and fund defaults, and saves
- **THEN** the settings are saved and the card lists the currency pairs in use and the next run time

#### Scenario: Feed on with no provider
- **WHEN** the entity admin turns on the price feed with no provider selected
- **THEN** saving is refused with "Choose at least one provider"

#### Scenario: Changing defaults leaves existing funds alone
- **WHEN** the entity admin changes the new-fund defaults to Manual + Market FX rates
- **THEN** existing funds keep their features and only funds created afterwards start with the new defaults

### Requirement: Fund feature flags
Each fund SHALL have one set of feature switches, stored and managed in the same way as the
entity's features, holding: show fund ratios to LPs, show fund units to LPs, show portfolio to LPs,
show valuations to LPs, AI commentary, editable formulas, accept market FX rates, accept derived FX
rates, accept market prices, derivatives, and use fund-specific FX rates. Accept market FX rates, accept market prices and
derivatives SHALL be available only when the matching entity feature is on; a submitted switch
whose entity feature is off SHALL be refused.

#### Scenario: Fund chooses its market-data features
- **WHEN** fund staff tick Accept market FX rates, Accept derived FX rates, Accept market prices and Derivatives on a fund whose entity has all three features, and save
- **THEN** the fund's Features section shows the choices and the fund's audit trail records the change

#### Scenario: Switch hidden when the entity feature is off
- **WHEN** the entity does not have Market FX rates on
- **THEN** the fund form shows no Accept market FX rates switch

#### Scenario: Direct submission of an unavailable switch
- **WHEN** a request sets Accept market prices on a fund whose entity lacks Market prices
- **THEN** the request is refused and the fund's features are unchanged

#### Scenario: Manual is always accepted
- **WHEN** fund staff view the fund's FX rate and price sources
- **THEN** Manual is shown ticked and cannot be unticked

#### Scenario: New fund starts with entity defaults
- **WHEN** a fund is created in an entity whose default is Manual + Market FX rates
- **THEN** the new fund accepts Manual and Market FX rates

### Requirement: Existing fund switches migrate into fund features
The system SHALL copy each fund's existing show fund ratios, show fund units, show portfolios, show
valuations, AI commentary and editable formulas values into the fund features without changing any
fund's value, and every screen, access rule and upload that used them SHALL behave exactly as
before.

#### Scenario: Values carried over
- **WHEN** the migration runs on a fund that showed portfolios and fund units to LPs but not fund ratios
- **THEN** the fund's features show portfolio and fund units on, fund ratios off

#### Scenario: Investor access unchanged
- **WHEN** an investor opens the portfolio of a fund with Show portfolio to LPs on, and of one with it off
- **THEN** they see the first fund's portfolio and are refused the second, as before

#### Scenario: Fund upload keeps its columns
- **WHEN** a fund upload sets "Show Fund Ratios To Lps" to Yes and "Show Fund Portfolios To Lps" to No
- **THEN** the created fund has Show fund ratios to LPs on and Show portfolio to LPs off

### Requirement: Fund limits for open-ended funds
An open-ended fund SHALL be able to set a maximum rate age (0–30 business days), a maximum price
age (0–30 business days) and a price-move threshold (1–100 %). A blank age or threshold SHALL use
the entity default. These limits SHALL NOT be shown for funds that are not open-ended. Derivative
limits are set in the fund's limit profile (see derivative-contracts).

#### Scenario: Blank limit uses entity default
- **WHEN** an open-ended fund leaves maximum rate age blank and the entity default is 3
- **THEN** the fund's effective maximum rate age is 3 business days

#### Scenario: Out-of-range age
- **WHEN** fund staff enter a maximum rate age of 31
- **THEN** saving is refused with "must be between 0 and 30"

#### Scenario: Out-of-range threshold
- **WHEN** fund staff enter a price-move threshold of 0
- **THEN** saving is refused with "must be between 1 and 100"

#### Scenario: Limits hidden on a closed-ended fund
- **WHEN** fund staff edit a fund that is not open-ended
- **THEN** the Limits group is not shown

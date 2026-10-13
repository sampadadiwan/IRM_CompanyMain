# Spec Delta

## Purpose

Lets a fund admin flag a fund as evergreen and record every dealing, payment, gate, lock-up, fee and journey term as a setting, with per-class overrides and presets. One model then fits different kinds of evergreen funds.

## ADDED Requirements

### Requirement: Make a fund evergreen
The system SHALL let a user with fund update rights make a fund evergreen, provided it has at least one unit class, and store the fund's evergreen settings. A fund without evergreen settings SHALL behave exactly as a closed-end fund does today.

#### Scenario: Make evergreen with a unit class
- **WHEN** a fund admin makes a fund with unit class "A" evergreen and saves the default settings with class A's initial price ₹10,000
- **THEN** the fund is evergreen, the message "This fund is now evergreen" is shown, and the fund shows its evergreen screens

#### Scenario: Fund has no unit class
- **WHEN** a fund admin opens Settings of a fund with no unit classes
- **THEN** there is no option to make it evergreen; instead it says "Add a unit class first" with a link to unit settings

#### Scenario: Closed-end fund is unchanged
- **WHEN** a user views a fund that is not evergreen
- **THEN** the fund's screens, labels, notices, calls, distributions and unit buttons behave as they did before this change

### Requirement: Evergreen settings and validation
The system SHALL hold and validate these fund settings:
- subscription and redemption dealing calendars, each Monthly, Quarterly, Semi-annual, Annual, or a custom list of dates;
- dealing day: first business day, last business day, or day N of the period, moved to the next business day;
- subscription payment timing: Before dealing, or After dealing within 1–30 days;
- subscription cut-off: 0–30 days;
- orders unpaid or not ready at cut-off: Roll or Cancel;
- order journeys: Off, Subscriptions, or Subscriptions and redemptions, with a template for each;
- redemption forms allowed: at least one of Units, Amount, All units;
- redemption settlement: 1–90 business days;
- gate: 0–100 %;
- gate level: Fund or Class;
- gate period: Per dealing date, Per calendar quarter, or Per year;
- gate method: FIFO or Pro-rata;
- investor-level gate: 0–100 % of holding;
- NAV ledger names: non-blank, defaults "Cash In Hand", "Net Current Assets", "Other Liabilities", "Management Fee Paid", "Performance Fee Paid";
- contract-note and redemption-advice templates.

Business days SHALL be Monday to Friday.

#### Scenario: Out-of-range gate
- **WHEN** a fund admin saves a gate of 120 %
- **THEN** the settings are not saved and the gate field shows that it must be between 0 and 100

#### Scenario: Defaults
- **WHEN** a fund admin makes a fund evergreen without changing any field
- **THEN** the settings are:
  - monthly subscriptions and quarterly redemptions, dealt on the first business day;
  - payment before dealing, with a 5-day cut-off;
  - unpaid orders rolled forward;
  - order journeys off;
  - all redemption forms allowed, settled within 10 business days;
  - no gate, at fund level, per dealing date, pro-rata, with no investor-level gate

#### Scenario: Custom dealing dates
- **WHEN** the redemption calendar is set to the custom dates 31 Mar 2027 and 30 Sep 2027
- **THEN** only those dates are offered as redemption dealing dates

#### Scenario: No redemption form allowed
- **WHEN** a fund admin clears Units, Amount and All units
- **THEN** the settings are not saved, with "Allow at least one way to redeem"

### Requirement: Per-class terms and overrides
The system SHALL hold per class:
- initial price (required, > 0);
- performance fee model (None or Class high-water mark);
- performance fee: 0–50 %;
- hurdle: 0–50 % a year, Hard or Soft;
- crystallisation: Quarterly, Semi-annual or Annual.

It SHALL allow per-class overrides of:
- notice period (0–180 days);
- lock-up (0–60 months, Hard or Soft);
- early-redemption fee: 0–10 % flat, or a schedule by unit age;
- minimum initial subscription;
- minimum additional subscription;
- minimum holding.

A class without an override SHALL use the fund value.

#### Scenario: Class override
- **WHEN** the fund notice period is 30 days and class B overrides it to 90 days
- **THEN** class B redemptions use 90 days and class A redemptions use 30 days

#### Scenario: Early-redemption fee schedule
- **WHEN** class A has a soft lock-up with a fee schedule of 3 % for units younger than 12 months and 2 % for units 12–24 months old
- **THEN** redeeming units 8 months old applies 3 % and units 18 months old applies 2 %

### Requirement: Presets
The system SHALL offer presets: Indian Cat III AIF, US evergreen / tender-offer fund, US interval fund, and Hedge-fund style. A preset SHALL only fill the form with the typical values listed in the proposal's Fund Setups table; every field SHALL stay editable before saving.

#### Scenario: Apply a preset
- **WHEN** a fund admin picks "US evergreen / tender-offer fund"
- **THEN** the form shows quarterly redemptions, payment before dealing, a 5 % fund-level gate per calendar quarter (pro-rata) and a 12-month soft lock-up with a 2 % fee, and nothing is saved until the admin clicks Save

### Requirement: Settings changes apply forward only
Changing settings SHALL affect only orders received after the change and dealing dates not yet confirmed. Confirmed dealing dates SHALL keep the settings they were confirmed with.

#### Scenario: Gate changed after confirmation
- **WHEN** a dealing date is confirmed with a 5 % gate and the admin then changes the gate to 10 %
- **THEN** the confirmed dealing date still shows a 5 % gate and the next unconfirmed one uses 10 %

### Requirement: Switch back only before the first confirmed dealing date
The system SHALL allow the evergreen flag to be removed only while the fund has no confirmed dealing date.

#### Scenario: Switch back after a confirmed dealing date
- **WHEN** a fund admin tries to make an evergreen fund with a confirmed dealing date closed-end again
- **THEN** the option is unavailable with "Dealing dates exist — cannot switch back"

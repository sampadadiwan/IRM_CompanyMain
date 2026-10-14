# Spec Delta

## Purpose

Lets a fund show each LP their own cost and FMV for every holding, company and total, read from the
LP's own folio allocations, using two allocation formulas the fund picks.

## ADDED Requirements

### Requirement: Your cost comes from the allocation formula; the fund picks a Your FMV formula
Under *Allocated, with their own share*, Your cost SHALL be read from the fund's allocation formula,
and the fund SHALL pick a different formula for Your FMV from the same set of holding-level
allocation formulas. Picks SHALL be kept when the view is changed and used again when it is changed
back. A picked formula SHALL keep working when renamed.

#### Scenario: Fund team picks the FMV formula
- **WHEN** a fund team member chooses *Allocated, with their own share* with "Allocated Portfolio Cost" as the allocation formula, picks "Allocated Portfolio FMV" for Your FMV and saves
- **THEN** the fund is saved and LPs see Your cost and Your FMV columns

#### Scenario: Missing FMV formula is refused
- **WHEN** a fund team member saves *Allocated, with their own share* without a Your FMV formula
- **THEN** the save is refused with "Choose the allocation formula that gives the LP's FMV."

#### Scenario: Same formula for both is refused
- **WHEN** the Your FMV formula is the same as the allocation formula
- **THEN** the save is refused with "Your cost and Your FMV must use different formulas."

#### Scenario: FMV formula outside the fund's holding allocation formulas is refused
- **WHEN** a request sets Your FMV to another fund's formula, a proforma formula, a company-level formula or a non-portfolio formula
- **THEN** the save is refused with "Pick one of this fund's portfolio allocation formulas."

#### Scenario: Picks kept when switching views
- **WHEN** the view is changed from *Allocated, with their own share* to *Whole fund portfolio* and back
- **THEN** the earlier formula picks are shown and used again

#### Scenario: Renamed formula keeps working
- **WHEN** a picked formula is renamed
- **THEN** LPs still see the same Your cost or Your FMV figures

#### Scenario: Deleted formula hides own share
- **WHEN** a picked formula is deleted
- **THEN** if it was the Your FMV formula, LPs see no Your columns; if it was the allocation formula, LPs see no holdings for the fund; and the fund page tells the fund team "Pick a new allocation formula" (or "Pick a new formula for Your FMV")

### Requirement: Own-share figures come from the LP's folio allocations
For each visible holding, Your cost and Your FMV SHALL be the LP's entries under the allocation formula
and the Your FMV formula respectively, taking for each folio and each allocated subject the entry with the latest reporting date on
or before today, ignoring deleted entries, and adding up instrument-level entries to their holding and
several folios of the same LP in the fund. Company and grand totals SHALL be the sum of the holding
figures. Figures SHALL be shown in the currency of the fund whose allocations produced them. The
multiple SHALL use the LP's figures when own share is shown.

#### Scenario: LP sees own cost and FMV
- **WHEN** an LP whose folio was allocated ₹2.50 Cr cost and ₹4.00 Cr FMV of Acme and ₹1.50 Cr / ₹1.80 Cr of Cedar opens the portfolio
- **THEN** the rows show those figures beside the fund's, Your totals read ₹4.00 Cr and ₹5.80 Cr, the multiple reads 1.45x, and a note names the two formulas and the latest reporting date

#### Scenario: Latest reporting date on or before today is used
- **WHEN** the folio has FMV entries for a holding dated 30/06/2026 (₹3.60 Cr) and 30/09/2026 (₹4.00 Cr)
- **THEN** Your FMV shows ₹4.00 Cr

#### Scenario: Future-dated entries are ignored
- **WHEN** the folio also has an FMV entry dated after today
- **THEN** it is not used

#### Scenario: Deleted entries are ignored
- **WHEN** the latest entry for a holding has been deleted
- **THEN** the latest remaining entry is used

#### Scenario: Instrument-level entries are summed to the holding
- **WHEN** a holding is made of two purchases allocated ₹1.00 Cr and ₹1.50 Cr cost to the folio
- **THEN** Your cost for the holding shows ₹2.50 Cr

#### Scenario: Aggregated-holding entries map directly
- **WHEN** the cost formula allocates at aggregated-holding level
- **THEN** Your cost for the holding is that entry's amount

#### Scenario: Several folios are added together
- **WHEN** an LP has two folios in the fund allocated ₹1.00 Cr and ₹0.50 Cr cost of a holding
- **THEN** Your cost shows ₹1.50 Cr

#### Scenario: Feeder folio uses the feeder fund's formulas
- **WHEN** an LP's folio is in a feeder fund whose view is *Allocated, with their own share* and the holding belongs to the master fund
- **THEN** Your cost and Your FMV come from the feeder fund's allocation and Your FMV formulas, in the feeder fund's currency

#### Scenario: Re-run allocation shows new figures
- **WHEN** an allocation run changes the folio's Acme cost from ₹2.50 Cr to ₹2.60 Cr
- **THEN** the LP sees ₹2.60 Cr on the next page load

### Requirement: Missing own-share entries are shown, not guessed
A visible holding with no entry under the Your FMV formula SHALL show "—" with the tooltip "Not yet
allocated to your folio" for that figure, SHALL be left out of the LP's totals for that figure, and the
totals SHALL say how many holdings were left out.

#### Scenario: Holding without an FMV entry shows a dash and is excluded from totals
- **WHEN** a holding is visible through its allocation-formula entry but has no entry under the Your FMV formula
- **THEN** Your FMV shows "—", the FMV total excludes it, and the note reads "Excludes 1 holding not yet allocated."

### Requirement: Where own share is shown
Your cost and Your FMV SHALL appear only under *Allocated, with their own share*, in the LP's holdings
list and its totals and on the company page holdings card. No other view SHALL show them.

#### Scenario: Own share columns absent in other views
- **WHEN** the fund's view is *Whole fund portfolio* or *Allocated to their folio*
- **THEN** no Your cost or Your FMV column appears anywhere for LPs

#### Scenario: Own share appears on company holdings card
- **WHEN** an LP opens a shared company under *Allocated, with their own share*
- **THEN** each holding row on the holdings card shows Your cost and Your FMV

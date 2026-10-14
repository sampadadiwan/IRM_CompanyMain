# Spec Delta

## Purpose

Lets a fund decide, in one setting, what its LPs see of the portfolio — nothing, the whole fund, or
only the holdings allocated to their own folio — and applies that choice identically on every LP
surface that shows portfolio holdings.

## ADDED Requirements

### Requirement: One LP portfolio view setting per fund
Each fund SHALL have a single "LP portfolio view" setting with exactly four options: *Hidden from
LPs*, *Whole fund portfolio*, *Allocated to their folio*, and *Allocated, with their own share*. It
SHALL replace the "Show fund portfolios to LPs" checkbox on the fund form. Existing funds SHALL show
*Whole fund portfolio* when portfolios were shown to LPs before the change and *Hidden from LPs*
otherwise, and SHALL behave exactly as before until the setting is changed. New funds SHALL default
to *Hidden from LPs*. Anything that reads or writes the previous "show portfolios" switch (uploads,
existing checks) SHALL keep working: *Hidden* means off, every other option means on.

#### Scenario: Existing fund that showed portfolios opens as Whole fund
- **WHEN** a fund team member opens the edit form of a fund whose portfolios were shown to LPs before the change
- **THEN** the LP portfolio view shows *Whole fund portfolio* and LPs see the same holdings as before

#### Scenario: Existing fund that hid portfolios opens as Hidden
- **WHEN** a fund team member opens the edit form of a fund whose portfolios were not shown to LPs
- **THEN** the LP portfolio view shows *Hidden from LPs*

#### Scenario: Fund team selects Allocated to their folio
- **WHEN** a fund team member with update permission chooses *Allocated to their folio*, picks "Allocated Portfolio Cost" as the allocation formula and saves
- **THEN** the fund is saved with that view and LPs see only holdings allocated to their folio

#### Scenario: Warning when no folio allocations exist
- **WHEN** a fund team member saves either *Allocated* option with an allocation formula that has no folio entries yet
- **THEN** the fund is saved and the form warns "No folio allocations found for this fund yet. LPs will see an empty portfolio until an allocation run completes."

#### Scenario: Legacy upload sets Whole fund
- **WHEN** a fund is uploaded with "Show Fund Portfolios To Lps" set to Yes, or a client sets the legacy show-portfolios switch on
- **THEN** the fund's LP portfolio view is *Whole fund portfolio*, unless it was an *Allocated* view before being hidden, in which case that view returns

### Requirement: Hidden view shows no portfolio
When a fund's LP portfolio view is *Hidden from LPs*, LPs SHALL see no portfolio section, no holdings
and no company pages for that fund, whatever other sharing switches are set.

#### Scenario: Hidden view hides portfolio
- **WHEN** an LP with access to a fund whose view is *Hidden from LPs* opens the fund
- **THEN** no portfolio section is shown and requests for that fund's holdings return no rows

### Requirement: Whole fund view is unchanged
When a fund's LP portfolio view is *Whole fund portfolio*, LPs SHALL see every holding of the fund,
exactly as before this change.

#### Scenario: Whole fund view lists every holding
- **WHEN** an LP opens the portfolio of a fund whose view is *Whole fund portfolio*
- **THEN** every holding of the fund is listed, including holdings the LP's folio was excused from, with the fund's figures only

### Requirement: Allocated views need an allocation formula
Either *Allocated* option SHALL require the fund to pick one **allocation formula**: one of the
fund's own non-proforma holding-level allocation formulas (instrument-level, master-fund
instrument-level, or aggregated-holding level). Other options SHALL keep but ignore the pick.

#### Scenario: Missing allocation formula is refused
- **WHEN** a fund team member saves *Allocated to their folio* without an allocation formula
- **THEN** the save is refused with "Choose the allocation formula that decides which holdings LPs see."

#### Scenario: Allocation formula outside the fund's holding allocation formulas is refused
- **WHEN** a request sets the allocation formula to another fund's formula, a proforma formula, a company-level formula or a non-portfolio formula
- **THEN** the save is refused with "Pick one of this fund's portfolio allocation formulas."

### Requirement: Allocated views list only holdings allocated to the LP's folio
When a fund's view is either *Allocated* option, a holding SHALL be visible to an LP only if at least
one of that LP's folios has an entry under the fund's allocation formula for that holding, of at least
one minor currency unit (positive or negative), dated on or before today and not deleted. Entries under
any other formula SHALL NOT make a holding visible. A company SHALL be visible when any of its holdings
is visible. For a folio in a feeder fund, master-fund holdings SHALL be visible through the feeder
fund's allocation formula; a feeder fund without one shows no master-fund holdings.

#### Scenario: Excused folio does not see the holding
- **WHEN** an LP's only folio has zero entries under the allocation formula for a holding it was excused from
- **THEN** that holding is not listed for the LP

#### Scenario: Holding not yet allocated is hidden
- **WHEN** a holding has no entries under the allocation formula for the LP's folios
- **THEN** the holding is not listed until an allocation run writes one

#### Scenario: Other formulas do not count
- **WHEN** the folio's allocation-formula entry for a holding is zero but another formula (e.g. an apportioned deal expense) gives it a non-zero amount
- **THEN** the holding is not listed

#### Scenario: Sub-unit allocations are ignored
- **WHEN** the folio's only allocation-formula entry for a holding is less than one minor currency unit
- **THEN** the holding is not listed

#### Scenario: Negative amounts count
- **WHEN** the folio's allocation-formula entry for a holding is negative
- **THEN** the holding is listed

#### Scenario: Exited holding stays visible
- **WHEN** the folio had a non-zero allocation-formula entry for a holding in an earlier quarter and zero at the latest date
- **THEN** the holding is listed

#### Scenario: Future-dated allocations are ignored for visibility
- **WHEN** the folio's only non-zero allocation-formula entry for a holding is dated after today
- **THEN** the holding is not listed

#### Scenario: Aggregated-holding allocation formula reveals the holding
- **WHEN** the allocation formula allocates at aggregated-holding level and gives the folio a non-zero amount
- **THEN** that holding is listed

#### Scenario: Company with several holdings shows only allocated ones
- **WHEN** a company has two holdings in the fund and the folio is allocated to only one
- **THEN** the company is listed and only the allocated holding appears under it

#### Scenario: Several folios are combined
- **WHEN** an LP has two folios in the fund, one excused from a holding and one allocated to it
- **THEN** the holding is listed

#### Scenario: LP with no folio sees an empty portfolio
- **WHEN** a user with access to the fund but no folio in it opens the portfolio under an *Allocated* view
- **THEN** the portfolio shows "No investments have been allocated to your folio yet."

#### Scenario: Feeder folio sees allocated master holdings
- **WHEN** an LP's folio is in a feeder fund and the feeder fund's allocation formula gives it a non-zero amount for a master-fund holding
- **THEN** that master-fund holding is listed for the LP

#### Scenario: Feeder fund without an allocation formula shows no master holdings
- **WHEN** the master fund's view is *Allocated to their folio* but the LP's feeder fund has no allocation formula picked
- **THEN** no master-fund holdings are listed for that LP

### Requirement: The same visible set applies everywhere
Every LP surface that lists or totals holdings for a fund under an *Allocated* view — holding lists,
aggregated lists, the fund's portfolio dashboard, totals, company pages and direct requests — SHALL use
the same visible set. Fund-wide portfolio charts that cannot be narrowed to the visible set SHALL NOT
be shown to LPs under an *Allocated* view. A banner SHALL name the LP's folio(s) in the fund.

#### Scenario: Totals add only visible holdings
- **WHEN** an LP views the portfolio under an *Allocated* view
- **THEN** the totals equal the sum of the listed holdings only, and the banner reads "Showing investments allocated to your folio (F-012)"

#### Scenario: Direct request for a hidden holding returns nothing
- **WHEN** an LP requests a hidden holding's list or detail address directly
- **THEN** no row is returned and the detail is refused

#### Scenario: Fund-wide charts are hidden under allocated views
- **WHEN** an LP opens the fund's portfolio dashboard under an *Allocated* view
- **THEN** fund-wide charts (FMV %, Holding Cost %, Bought %, Sold %, Portfolio IRR, fund Portfolio Stats) are not shown, and the holdings list with its totals is shown

#### Scenario: Re-run allocation updates visibility
- **WHEN** a new holding is allocated to the LP's folio by an allocation run
- **THEN** the holding is listed on the LP's next page load without any other action

### Requirement: LP assistant follows the visible set
The LP AI assistant SHALL answer questions about portfolio holdings only from holdings visible to that
LP, and SHALL NOT read holdings of funds whose view is *Hidden from LPs*.

#### Scenario: Assistant answers only from visible holdings
- **WHEN** an LP asks the assistant about a holding hidden from them under an *Allocated* view
- **THEN** the assistant's query returns no rows for that holding

#### Scenario: Portfolio query without visibility scope is rejected
- **WHEN** the assistant generates a query on holdings without the visible-holdings scope
- **THEN** the query is rejected and no data is returned

### Requirement: Portfolio settings follow the fund-portfolios module
The fund form SHALL show the LP portfolio view and Portfolio valuations only when the fund manager has the
fund-portfolios module. Without it, their stored values SHALL be kept, and a request submitting them SHALL be
refused or ignored.

#### Scenario: Portfolio settings need the fund-portfolios module
- **WHEN** a fund manager without the fund-portfolios module saves a fund's Features step
- **THEN** the LP portfolio view and Portfolio valuations are not shown, and their stored values are unchanged

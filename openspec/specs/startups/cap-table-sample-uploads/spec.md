# startups/cap-table-sample-uploads Specification

## Purpose
Keeps the sample files offered on the cap table upload pages in the current import format, so
a user can fill one in and upload it without errors.

## Requirements

### Requirement: Investments sample file
The "Upload Investments" page SHALL offer `/sample_uploads/investments.xlsx`. The file SHALL
include the `SubGroup`, `Instrument Name` and `Instrument Quantity` columns. It SHALL import
without errors for a portfolio company named in the file.

#### Scenario: Sample imported as-is
- **WHEN** the investments sample is uploaded for portfolio company "AX"
- **THEN** both rows are imported
- **AND** the Convertible row has subgroup "Institutional", instrument "CCPS Series A" and instrument quantity 15
- **AND** the Equity row has no subgroup or instrument details
- **AND** no custom fields are created for the subgroup or instrument columns

### Requirement: Shareholder positions sample file
The "Upload Shareholding Patterns" page SHALL offer `/sample_uploads/shareholder_positions.xlsx`.
The file SHALL:
- use the Stakeholder, ShareHolder, Category, Subgroup, Instrument, As Of, Quantity Actuals, Fully Dilluted Quantity and Fully Dilluted % columns
- import without errors for the portfolio company named in the file
- cover both a dated As Of snapshot and a round-name As Of snapshot

#### Scenario: Sample imported as-is
- **WHEN** the shareholder positions sample is uploaded for portfolio company "Ace Ltd"
- **THEN** all 15 rows are imported, including the 2025-12-31 and "Series A" snapshots
- **AND** the positions keep their subgroup, instrument, quantity actuals and fully diluted quantity
- **AND** the horizontal cap table nests "Seed Ventures LP" under "Institutional" and "Angel Syndicate" under "Angel"

# startups/cap-table-actions Specification

## Purpose
Controls which upload, view and download actions the cap table page offers. A portfolio
company's cap table is built from one kind of data, and download buttons only appear when there
is something to download.

## Requirements

### Requirement: Entry points follow the company's data
On a portfolio company's cap table page:
- **Investment actions** (New Investment, Upload Investments, View Investments) SHALL be hidden
  once the company has approved shareholder positions.
- **Shareholding actions** (Upload Shareholding Patterns, View Shareholding Patterns) SHALL be
  hidden once the company has investments.
- Shareholder positions awaiting approval SHALL NOT count as data.
- The investments list outside a portfolio company SHALL offer every action.

#### Scenario: Company with investments
- **WHEN** a company has investments
- **THEN** its cap table page offers the investment actions and no shareholding actions

#### Scenario: Company with approved shareholder positions
- **WHEN** a company has approved shareholder positions
- **THEN** its cap table page offers the shareholding actions and no investment actions

#### Scenario: Unapproved shareholder positions only
- **WHEN** a company's only data is shareholder positions awaiting approval
- **THEN** its cap table page offers both Upload Investments and Upload Shareholding Patterns

#### Scenario: Investments list outside a company
- **WHEN** a user opens the investments list without a portfolio company
- **THEN** every upload, view and download action is offered

### Requirement: Downloads only when there is data
"Download Investments" and "Download Shareholding Patterns" SHALL NOT be shown for a portfolio
company that has neither investments nor approved shareholder positions. Otherwise each SHALL be
shown alongside its own kind's actions.

#### Scenario: Company with no data
- **WHEN** a company has no investments and no approved shareholder positions
- **THEN** its cap table page offers both upload and view entry points and no download buttons

#### Scenario: Download alongside the data
- **WHEN** a company has investments
- **THEN** "Download Investments" is shown
- **WHEN** a company has approved shareholder positions instead
- **THEN** "Download Shareholding Patterns" is shown

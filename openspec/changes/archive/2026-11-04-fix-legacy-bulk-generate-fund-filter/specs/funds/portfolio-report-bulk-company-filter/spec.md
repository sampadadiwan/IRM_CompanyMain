# Spec Delta

## Purpose

Defines how the legacy bulk portfolio report page selects portfolio companies when a user previews with Fund, Tag and Sector filters.

## ADDED Requirements

### Requirement: Fund filter selects companies with investments in the chosen funds
When previewing with one or more Funds, the system SHALL select exactly the entity's portfolio companies that have at least one portfolio investment in any chosen fund, and SHALL render the page without error.

#### Scenario: Preview with a fund
- **WHEN** a user previews with a fund that has investments in companies A and B but not C
- **THEN** A and B are selected, C is not, and no error is shown

#### Scenario: Company with multiple investments in the fund
- **WHEN** a user previews with a fund in which company A has three investments
- **THEN** company A is selected once

#### Scenario: Fund with no investments
- **WHEN** a user previews with a fund that has no portfolio investments
- **THEN** no companies are selected and no error is shown

### Requirement: Filters combine and the company list is unaffected
The system SHALL combine Fund, Tag and Sector filters so that a company is selected only if it satisfies every filter provided, and SHALL keep listing all portfolio companies alphabetically regardless of filters.

#### Scenario: Fund and sector together
- **WHEN** a user previews with a fund and a sector
- **THEN** only companies in that fund and that sector are selected

#### Scenario: No fund chosen
- **WHEN** a user previews with no fund
- **THEN** fund filtering is not applied and the company list order is unchanged

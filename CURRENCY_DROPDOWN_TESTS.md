# Currency Dropdown Test Implementation Summary

## Overview
Created comprehensive Cucumber feature tests and step definitions for the `show_currency_filter` metadata parameter across three dashboard widgets.

## Feature File
**Location**: `/home/anios/IRM/features/fund/currency_dropdown_visibility.feature`

### Test Scenarios (6 total)

#### 1. Fund Ratios Widget
- **Show dropdown**: `show_currency_filter: true` → Currency dropdown visible
- **Hide dropdown**: `show_currency_filter: false` → Currency dropdown hidden
- **Selector**: `select#metrics_filter_select`

#### 2. Portfolio Stats Widget
- **Show dropdown**: `show_currency_filter: true` → Currency dropdown visible
- **Hide dropdown**: `show_currency_filter: false` → Currency dropdown hidden
- **Selector**: `select[data-portfolio-stats-currency-target="select"]`

#### 3. Portfolio Company Report Widget (Valuations)
- **Show dropdown**: `show_currency_filter: true` → Currency dropdown visible
- **Hide dropdown**: `show_currency_filter: false` → Currency dropdown hidden
- **Selector**: `select[id^="valuation_currency_select"]`

## Step Definitions
**Location**: `/home/anios/IRM/features/step_definitions/currency_dropdown_steps.rb`

### New Steps Added

#### Widget Configuration Steps:
- `Given the Fund Ratios widget has metadata {string}` - Configures Fund Ratios widget with custom metadata
- `Given the Portfolio Stats widget has metadata {string}` - Configures Portfolio Stats widget with custom metadata
- `Given the Portfolio Company Report widget has metadata with show_currency_filter true` - Configures valuation report with filter enabled
- `Given the Portfolio Company Report widget has metadata with show_currency_filter false` - Configures valuation report with filter disabled

#### Assertion Steps:
- `Then I should see a currency dropdown for fund ratios` - Verifies Fund Ratios dropdown is visible
- `Then I should not see a currency dropdown for fund ratios` - Verifies Fund Ratios dropdown is hidden
- `Then I should see a currency dropdown for portfolio stats` - Verifies Portfolio Stats dropdown is visible
- `Then I should not see a currency dropdown for portfolio stats` - Verifies Portfolio Stats dropdown is hidden
- `Then I should see a currency dropdown for valuations` - Verifies Valuations dropdown is visible
- `Then I should not see a currency dropdown for valuations` - Verifies Valuations dropdown is hidden

## Widget Metadata Examples

### Fund Ratios
```ruby
metadata: "{scenarios: true, condensed: true, chart: false, title: 'Ratios: Actual', hide_search: true, months: 6, show_currency_filter: true}"
```

### Portfolio Stats
```ruby
metadata: "{force_units: 'Millions', fields: 'Bought Amount,Sold Amount,FMV,Cost of Remaining', show_currency_filter: true}"
```

### Portfolio Company Report (Valuations via Fund Report widget)
```ruby
metadata: "{report_id: #{@valuation_report.id}, show_currency_filter: true}"
```

## Running the Tests

### Dry Run (verify step definitions)
```bash
bundle exec cucumber features/fund/currency_dropdown_visibility.feature --dry-run
```

### Run All Scenarios
```bash
bundle exec cucumber features/fund/currency_dropdown_visibility.feature
```

### Run Specific Scenarios
```bash
# Fund Ratios - show dropdown
bundle exec cucumber features/fund/currency_dropdown_visibility.feature:9

# Fund Ratios - hide dropdown
bundle exec cucumber features/fund/currency_dropdown_visibility.feature:19

# Portfolio Stats - show dropdown
bundle exec cucumber features/fund/currency_dropdown_visibility.feature:29

# Portfolio Stats - hide dropdown
bundle exec cucumber features/fund/currency_dropdown_visibility.feature:37

# Valuations - show dropdown
bundle exec cucumber features/fund/currency_dropdown_visibility.feature:45

# Valuations - hide dropdown
bundle exec cucumber features/fund/currency_dropdown_visibility.feature:53
```

## Implementation Notes

1. **Fund Ratios**: Uses `params[:show_currency_filter]` in the fund_ratios partial to conditionally render the currency dropdown.

2. **Portfolio Stats**: Uses `args[:show_currency_filter]` from widget metadata and conditionally renders the currency dropdown in the stats partial.

3. **Portfolio Company Report (Valuations)**: Uses the Fund Report widget which appends `show_currency_filter=true` to the report URL if the metadata specifies it. The valuations time_series partial then checks this param.

4. **Widget Names**:
   - Fund Ratios widget: `'Fund Ratios'`
   - Portfolio Stats widget: `'Portfolio Stats'`
   - Valuations widget: `'Fund Report'` (displays valuation reports)

5. **Dashboard Context**: All tests run on the Portfolio Company Dashboard (`/investors/:id/dashboard`)

## Test Data Setup

Each scenario creates:
- User with `company_admin` role
- Entity with USD currency
- Fund associated with the entity
- Portfolio company (Investor category)
- Investment instrument
- Widget-specific data (fund ratios, portfolio investments, or valuations)
- Dashboard widget configuration with appropriate metadata

## Next Steps

To run the tests:
```bash
cd /home/anios/IRM
bundle exec cucumber features/fund/currency_dropdown_visibility.feature
```

Expected behavior:
- When `show_currency_filter: true` → Currency dropdown should be visible on the page
- When `show_currency_filter: false` → Currency dropdown should NOT be visible on the page

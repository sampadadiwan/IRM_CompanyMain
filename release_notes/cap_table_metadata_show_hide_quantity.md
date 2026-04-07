# Cap Table Widget - Quantity Columns Configuration

## Overview
The Cap Table widget now supports showing/hiding the last two quantity columns independently through metadata configuration.

## Metadata Parameters

### `show_quantity_actual`
- **Type:** Boolean (passed as string "true" or "false")
- **Default:** `true` (column is shown)
- **Description:** Controls visibility of the "Quantity actual (as on the latest round)" column

### `show_quantity_diluted`
- **Type:** Boolean (passed as string "true" or "false")
- **Default:** `true` (column is shown)
- **Description:** Controls visibility of the "Quantity- fully diluted (as on the latest round)" column

## Usage Examples

### Example 1: Show Both Columns (Default)
```ruby
metadata = "{}"
# OR explicitly
metadata = "{show_quantity_actual: true, show_quantity_diluted: true}"
```

Both quantity columns will be visible in the cap table display.

### Example 2: Hide Both Columns
```ruby
metadata = "{show_quantity_actual: false, show_quantity_diluted: false}"
```

Both quantity columns will be hidden.

### Example 3: Show Only Actual Quantity
```ruby
metadata = "{show_quantity_actual: true, show_quantity_diluted: false}"
```

Only the "Quantity actual" column will be shown; the "Quantity diluted" column will be hidden.

### Example 4: Show Only Diluted Quantity
```ruby
metadata = "{show_quantity_actual: false, show_quantity_diluted: true}"
```

Only the "Quantity- fully diluted" column will be shown; the "Quantity actual" column will be hidden.

## Widget Configuration in Dashboard

When configuring the Cap Table widget in a dashboard:

1. Navigate to the dashboard widget configuration
2. Set the widget type to "Cap Table"
3. In the metadata field, enter one of the following:
   - `{}` - Show both columns (default)
   - `{show_quantity_actual: false, show_quantity_diluted: false}` - Hide both columns
   - `{show_quantity_actual: true, show_quantity_diluted: false}` - Show only actual quantity
   - `{show_quantity_actual: false, show_quantity_diluted: true}` - Show only diluted quantity

## Implementation Details

### Files Modified
1. **Widget Template:** `app/packs/startups/investments/views/investments/widgets/_captable.html.erb`
   - Includes `args ||= widget.metadata_args` to pass metadata parameters

2. **Horizontal Cap Table Partial:** `app/packs/startups/investments/views/investments/_horizontal_captable.html.erb`
   - Reads `params[:show_quantity_actual]` and `params[:show_quantity_diluted]` parameters
   - Conditionally applies `style="display: none;"` to respective column headers and cells when parameter is "false"

### How It Works
1. Widget metadata is parsed into `metadata_args` hash
2. Parameters are passed through the URL query string when loading the turbo frame
3. The `_horizontal_captable` partial checks for each parameter: `params[:show_quantity_actual] != "false"` and `params[:show_quantity_diluted] != "false"`
4. Each column is independently shown (default) or hidden based on its corresponding parameter

## Testing

To test this functionality:

1. Create or edit a Cap Table widget on a dashboard
2. Test each scenario:
   - Leave metadata empty → verify both columns visible
   - Set `{show_quantity_actual: false}` → verify only actual column hidden
   - Set `{show_quantity_diluted: false}` → verify only diluted column hidden
   - Set `{show_quantity_actual: false, show_quantity_diluted: false}` → verify both columns hidden

## Test Overview
Created comprehensive Cucumber feature tests to verify the cap table quantity columns visibility functionality.

## Test Files Created

### 1. Feature File: `features/startup/captable_quantity_columns.feature`

**Purpose:** Test the independent visibility control of two quantity columns in the cap table widget.

**Test Coverage:**
- 7 test scenarios covering all combinations of column visibility
- Tests both default behavior and explicit parameter settings

**Scenarios:**

1. **View cap table with both quantity columns visible (default)**
   - Verifies default behavior shows both columns when no parameters are provided
   - Expected: Both columns visible

2. **View cap table with show_quantity_actual=true and show_quantity_diluted=true**
   - Explicitly sets both parameters to true
   - Expected: Both columns visible

3. **Hide both quantity columns**
   - Sets both parameters to false
   - Expected: Both columns hidden

4. **Show only quantity actual column**
   - show_quantity_actual=true, show_quantity_diluted=false
   - Expected: Only "Quantity actual" visible

5. **Show only quantity diluted column**
   - show_quantity_actual=false, show_quantity_diluted=true
   - Expected: Only "Quantity- fully diluted" visible

6. **Hide only quantity actual column**
   - Only sets show_quantity_actual=false
   - Expected: "Quantity actual" hidden, "Quantity- fully diluted" visible (default)

7. **Hide only quantity diluted column**
   - Only sets show_quantity_diluted=false
   - Expected: "Quantity actual" visible (default), "Quantity- fully diluted" hidden

### 2. Step Definitions: `features/step_definitions/investment.rb`

**New Steps Added:**

#### Navigation Step
```ruby
When('I go to the captable with params {string}')
```
- Navigates to the cap table with specified URL parameters
- Builds URL with portfolio_company_id and show_captable=true
- Appends custom parameters for show_quantity_actual and show_quantity_diluted

#### Verification Steps

**Positive Assertions (should see):**
```ruby
Then('I should see the quantity actual column header')
Then('I should see the quantity diluted column header')
Then('I should see quantity values in the table')
```

**Negative Assertions (should not see):**
```ruby
Then('I should not see the quantity actual column header')
Then('I should not see the quantity diluted column header')
```

**Implementation Details:**
- Uses Capybara selectors to find table headers within `.show_horizontal_cap_table`
- Checks for `display: none` inline style to determine visibility
- Uses regex patterns to match header text (handles variations in spacing)
- Validates that headers exist and are not hidden with CSS
- For "should not see" steps, accepts either hidden elements or no elements at all

## Test Data Setup

**Background Setup:**
- Creates a test entity "Startup Inc"
- Creates a portfolio company record
- Sets up 3 investments across 2 funding rounds:
  - Startup Inc (Self, Seed): 1,000,000 shares @ $0.01
  - John Doe (Employee, Seed): 100,000 shares @ $0.10
  - VC Fund (Other, Series A): 200,000 shares @ $1.00

This data ensures:
- Multiple categories (Self, Employee, Other)
- Multiple funding rounds (Seed, Series A)
- Sufficient data to populate the horizontal cap table
- Realistic quantity values to verify visibility

## Running the Tests

### Run all cap table quantity column tests:
```bash
bundle exec cucumber features/startup/captable_quantity_columns.feature
```

### Run a specific scenario:
```bash
bundle exec cucumber features/startup/captable_quantity_columns.feature:11  # Line number of scenario
```

### Run with detailed output:
```bash
bundle exec cucumber features/startup/captable_quantity_columns.feature --format pretty
```

## Expected Test Results

All 7 scenarios should pass, verifying:
- ✅ Default behavior shows both columns
- ✅ Explicit true parameters show columns
- ✅ False parameters hide columns
- ✅ Independent control of each column works correctly
- ✅ Partial parameter specification works (unspecified defaults to true/visible)

## Integration with Existing Tests

The new tests:
- Reuse existing step definitions for setup (user login, portfolio company creation, investment creation)
- Follow the same pattern as existing cap table tests in `features/startup/captable.feature`
- Use the same Capybara matchers and expectations
- Maintain consistency with the project's testing conventions

## Notes for Developers

1. **CSS Selectors:** Tests rely on the `.show_horizontal_cap_table` CSS class
2. **Header Text:** Tests match headers using regex to handle spacing variations
3. **Style Attribute:** Tests check for inline `style="display: none;"` attribute
4. **Table Structure:** Tests assume quantity columns use `td.text-right` class
5. **Default Behavior:** Tests verify that omitting a parameter defaults to showing the column

## Troubleshooting

If tests fail:
1. Verify the cap table is rendering with the correct CSS class
2. Check that inline styles are being applied correctly
3. Ensure header text exactly matches the template
4. Verify URL parameters are being passed correctly
5. Check that the horizontal cap table partial is using the correct parameter names


## Related Features

This implementation follows the same pattern as other metadata-driven features like:
- `show_currency_filter` for currency dropdown visibility
- `tabs` for portfolio report section filtering

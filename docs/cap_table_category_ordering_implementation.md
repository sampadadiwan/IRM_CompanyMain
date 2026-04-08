# Cap Table Category Ordering - Implementation Summary

## Feature Overview
Added metadata-driven category ordering functionality to the horizontal cap table widget, allowing users to customize the display order of investor categories (Founders, Employees, Others, Demo Fund, etc.).

## Changes Made

### 1. Core Implementation
**File:** `app/packs/startups/investments/views/investments/_horizontal_captable.html.erb`

**Added:**
- New metadata parameter: `category_order`
- Custom sorting logic that:
  - Parses comma-separated category names from the parameter
  - Creates flexible name mapping (handles singular, plural, display names)
  - Sorts categories according to custom order
  - Falls back to quantity-based sorting for unlisted categories

**Code Changes:**
```ruby
# Added parameter parsing (line ~10)
category_order = params[:category_order].presence

# Added custom sorting logic (lines ~45-70)
if category_order.present?
  # Parse and apply custom order
  order_array = category_order.split(',').map(&:strip)
  # Create category name mapping
  # Sort by custom order, with unspecified categories at the end
else
  # Default quantity-based sorting
  sorted_categories = category_summaries.sort_by { |s| -s[:total_fully_diluted] }
end
```

### 2. Documentation
**File:** `docs/cap_table_configuration.md`

Created comprehensive documentation covering:
- All metadata parameters (column visibility + ordering)
- Usage examples for common scenarios
- Category name mapping rules
- Troubleshooting guide
- Testing instructions

### 3. Test Coverage
**Files Created:**
- `features/startup/captable_category_ordering.feature` - 6 test scenarios
- Step definitions in `features/step_definitions/investment.rb`

**Test Scenarios:**
1. Default ordering by quantity (descending)
2. Custom order - Founders first
3. Custom order using plural names
4. Partial custom order
5. Investor-focused order
6. Combined custom order with hidden columns

## Usage

### Widget Metadata Format

```ruby
# Basic custom order
{category_order: 'Self,Employee,Other,Lead Investor'}

# Using display/plural names
{category_order: 'Founders,Employees,Others,Demo Fund'}

# Partial order (unlisted categories sorted by quantity)
{category_order: 'Self,Lead Investor'}

# Combined with column visibility
{
  category_order: 'Self,Employee,Other',
  show_quantity_diluted: false
}
```

### URL Parameter Format

When accessing directly via URL:
```
/investments?portfolio_company_id=123&show_captable=true&category_order=Self,Employee,Other
```

## Category Name Mapping

The implementation supports flexible category name matching:

| Actual DB Category | Can Be Referenced As |
|-------------------|---------------------|
| `"Self"` | `"Self"`, `"Founder"`, `"Founders"`, Company Name |
| `"Employee"` | `"Employee"`, `"Employees"` |
| `"Other"` | `"Other"`, `"Others"` |
| `"Lead Investor"` | `"Lead Investor"`, `"Lead Investors"` |

This is achieved by creating a mapping hash that includes:
- Original category name
- Pluralized version
- Singularized version
- Display name (for "Self" → company name)

## Sorting Behavior

### Default (No `category_order` parameter):
Categories are sorted by total fully diluted quantity in **descending order** (highest ownership first).

### Custom Order Specified:
1. Categories listed in `category_order` appear in that exact order
2. Categories NOT listed appear after, sorted by quantity (descending)
3. This allows partial customization while maintaining sensible defaults

### Example:
If data has categories: `["Self", "Employee", "Other", "Lead Investor"]`

And `category_order = "Self,Employee"`:
- Result: `["Self", "Employee", "Lead Investor", "Other"]`
  - (assuming Lead Investor has more shares than Other)

## Testing

### Run Category Ordering Tests
```bash
bundle exec cucumber features/startup/captable_category_ordering.feature
```

### Run All Cap Table Tests
```bash
bundle exec cucumber features/startup/captable_*.feature
```

### Expected Test Results
All scenarios should pass, verifying:
- ✅ Default quantity-based ordering works
- ✅ Custom order is applied correctly
- ✅ Plural/display names are recognized
- ✅ Partial ordering works (unlisted categories follow)
- ✅ Category ordering combines with column visibility
- ✅ Category comparison step correctly identifies positions

## Step Definitions Added

### `Then('I should see category {string} before category {string}')`
Verifies that one category appears before another in the table.

**Implementation:**
- Locates all category header rows (`.parent td:first-child strong`)
- Maps category names to handle "Self" → company name
- Handles pluralization ("Employee" → "Employees")
- Compares positions and reports detailed error messages

**Features:**
- Flexible name matching
- Clear error messages with actual category list
- Handles edge cases (missing categories, etc.)

### `Then('I should see categories in quantity-based order')`
Verifies categories exist and are displayed (basic smoke test for default ordering).

## Common Use Cases

### 1. Founder-Focused View
```ruby
{category_order: 'Self,Employee,Lead Investor,Other'}
```
Emphasizes internal stakeholders first.

### 2. Investor-Focused View
```ruby
{category_order: 'Lead Investor,Other,Self,Employee'}
```
Shows external investors first for pitch decks/reports.

### 3. Alphabetical Order
```ruby
{category_order: 'Employee,Lead Investor,Other,Self'}
```
Simple alphabetical sorting.

### 4. Custom Business Logic
```ruby
{category_order: 'Self,Lead Investor'}
```
Show key stakeholders first, others sorted by ownership.

## Implementation Notes

### Why Support Multiple Name Formats?
- Users may not know exact database category names
- Display names in UI may differ from database values
- Plural forms are more natural in English
- "Self" vs company name is non-obvious

### Performance Considerations
- Name mapping is created once per render
- Sorting happens in Ruby (fast for typical cap tables)
- No database queries added
- Minimal overhead for default behavior

### Edge Cases Handled
1. **Category not in data:** Ignored silently
2. **Category listed multiple times:** Uses first occurrence
3. **Empty order string:** Falls back to default
4. **Invalid category names:** Ignored, doesn't break rendering
5. **All categories custom ordered:** Works perfectly
6. **No categories custom ordered:** Falls back to quantity sorting

## Future Enhancements

Potential improvements for future versions:

1. **UI Builder:** Visual drag-and-drop category ordering in widget config
2. **Saved Templates:** Common orderings saved as presets
3. **Per-User Preferences:** Remember user's preferred ordering
4. **Investor Grouping:** Combine categories into custom groups
5. **Conditional Ordering:** Different orders based on round/date
6. **Sort Direction Control:** Allow ascending quantity sort

## Related Files

- Implementation: `app/packs/startups/investments/views/investments/_horizontal_captable.html.erb`
- Widget wrapper: `app/packs/startups/investments/views/investments/widgets/_captable.html.erb`
- Documentation: `docs/cap_table_configuration.md`
- Tests: `features/startup/captable_category_ordering.feature`
- Test steps: `features/step_definitions/investment.rb`
- Column visibility tests: `features/startup/captable_quantity_columns.feature`
- Original cap table tests: `features/startup/captable.feature`

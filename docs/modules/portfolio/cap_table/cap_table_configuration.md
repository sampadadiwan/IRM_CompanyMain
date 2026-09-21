# Cap Table Widget - Configuration Guide

## Overview
The Cap Table widget supports customizing the display through metadata configuration, including column visibility and category ordering.

## Metadata Parameters

### Column Visibility

#### `show_quantity_actual`
- **Type:** Boolean (passed as string "true" or "false")
- **Default:** `true` (column is shown)
- **Description:** Controls visibility of the "Quantity actual (as on the latest round)" column

#### `show_quantity_diluted`
- **Type:** Boolean (passed as string "true" or "false")
- **Default:** `true` (column is shown)
- **Description:** Controls visibility of the "Quantity- fully diluted (as on the latest round)" column

### Category Ordering

#### `category_order`
- **Type:** String (comma-separated list of category names)
- **Default:** `null` (sorts by total fully diluted quantity descending)
- **Description:** Defines the display order of investor categories in the cap table
- **Format:** `"Category1,Category2,Category3"`
- **Examples:**
  - `"Self,Employee,Other,Lead Investor"`
  - `"Founders,Employees,Others,Demo Fund"`
  - `"Self,Lead Investor,Employee"`

**Behavior:**
- Categories listed in the order string appear in that specified order from top to bottom
- Categories not listed in the order appear after the ordered ones, sorted by quantity (descending)
- Supports multiple name formats:
  - Original category names: `"Self"`, `"Employee"`, `"Other"`, `"Lead Investor"`
  - Plural forms: `"Employees"`, `"Others"`
  - Display names: For "Self" category, you can use the portfolio company's name
- Case-sensitive matching with flexible fallback

## Usage Examples

### Example 1: Show Both Columns with Default Ordering (Default)
```ruby
metadata = "{}"
# OR explicitly
metadata = "{show_quantity_actual: true, show_quantity_diluted: true}"
```
- Both quantity columns visible
- Categories sorted by total fully diluted quantity (highest first)

### Example 2: Hide Both Quantity Columns
```ruby
metadata = "{show_quantity_actual: false, show_quantity_diluted: false}"
```
- Both quantity columns hidden
- Default category ordering

### Example 3: Custom Category Order - Founders First
```ruby
metadata = "{category_order: 'Self,Employee,Other,Lead Investor'}"
```
- Shows Founders (Self) first
- Then Employees
- Then Others
- Then Lead Investors
- Any other categories appear last, sorted by quantity

### Example 4: Custom Category Order with Display Names
```ruby
metadata = "{category_order: 'Founders,Employees,Others,Demo Fund'}"
```
- Uses plural/display names
- System automatically maps:
  - "Founders" → "Self" category
  - "Employees" → "Employee" category
  - "Others" → "Other" category
  - "Demo Fund" → "Lead Investor" category (if that's the actual category name)

### Example 5: Partial Custom Order
```ruby
metadata = "{category_order: 'Self,Employee'}"
```
- Shows Self first, then Employee
- All other categories appear after, sorted by quantity descending

### Example 6: Hide One Column with Custom Order
```ruby
metadata = "{show_quantity_diluted: false, category_order: 'Self,Other,Employee'}"
```
- Hides "Quantity- fully diluted" column
- Shows categories in specified order

### Example 7: Complex Configuration
```ruby
metadata = "{
  show_quantity_actual: true,
  show_quantity_diluted: false,
  category_order: 'Founders,Demo Fund,Others,Employees'
}"
```
- Shows only "Quantity actual" column
- Custom category order with display names

## Widget Configuration in Dashboard

When configuring the Cap Table widget in a dashboard:

1. Navigate to the dashboard widget configuration
2. Set the widget type to "Cap Table"
3. In the metadata field, enter your desired configuration:

**For column visibility:**
- `{show_quantity_actual: false}` - Hide actual quantity column
- `{show_quantity_diluted: false}` - Hide diluted quantity column
- `{show_quantity_actual: false, show_quantity_diluted: false}` - Hide both

**For category ordering:**
- `{category_order: 'Self,Employee,Other'}` - Custom order
- `{category_order: 'Founders,Employees,Others,Demo Fund'}` - Using display names

**Combined:**
```ruby
{
  show_quantity_actual: true,
  show_quantity_diluted: false,
  category_order: 'Self,Lead Investor,Employee,Other'
}
```

## Implementation Details

### Files Modified
1. **Widget Template:** `app/packs/startups/investments/views/investments/widgets/_captable.html.erb`
   - Includes `args ||= widget.metadata_args` to pass metadata parameters

2. **Horizontal Cap Table Partial:** `app/packs/startups/investments/views/investments/_horizontal_captable.html.erb`
   - Reads `params[:show_quantity_actual]`, `params[:show_quantity_diluted]`, and `params[:category_order]`
   - Conditionally applies `style="display: none;"` to quantity columns based on parameters
   - Implements custom category sorting when `category_order` is provided
   - Falls back to quantity-based sorting for unlisted categories

### How Category Ordering Works

1. Parse the `category_order` parameter into an array
2. Create a mapping of all possible category name variations (singular, plural, display name)
3. For each category in the data:
   - Check if it appears in the custom order (using any name format)
   - If found, use that position in the order
   - If not found, place after custom-ordered items, sorted by quantity
4. Render categories in the final sorted order

### Category Name Mapping Examples

| Actual Category | Recognized As |
|----------------|---------------|
| `"Self"` | `"Self"`, `"Founder"`, `"Founders"`, Portfolio Company Name |
| `"Employee"` | `"Employee"`, `"Employees"` |
| `"Other"` | `"Other"`, `"Others"` |
| `"Lead Investor"` | `"Lead Investor"`, `"Lead Investors"` |

## Testing

### Manual Testing Steps

1. **Test Default Behavior:**
   - Create a cap table widget with no metadata
   - Verify categories are sorted by quantity (descending)
   - Verify both quantity columns are visible

2. **Test Custom Category Order:**
   - Set `category_order: "Self,Employee,Other"`
   - Verify categories appear in that order
   - Verify ordering persists when data changes

3. **Test Column Visibility:**
   - Set `show_quantity_actual: false`
   - Verify the "Quantity actual" column is hidden
   - Verify other columns remain visible

4. **Test Combined Configuration:**
   - Use both column visibility and category ordering
   - Verify both features work together correctly

### Automated Tests

Refer to `CAP_TABLE_TESTS.md` for Cucumber feature tests covering:
- Column visibility scenarios
- Category ordering scenarios (to be added)

## Common Category Orders

Based on typical use cases, here are recommended orderings:

### Founder-Focused View
```ruby
{category_order: 'Self,Employee,Lead Investor,Other'}
```
Emphasizes founders and employees, then investors.

### Investor-Focused View
```ruby
{category_order: 'Lead Investor,Other,Self,Employee'}
```
Emphasizes external investors first.

### Alphabetical Order
```ruby
{category_order: 'Employee,Lead Investor,Other,Self'}
```
Simple alphabetical ordering.

### Ownership Percentage View
```ruby
{}
```
Leave empty to use default quantity-based sorting.

## Troubleshooting

### Categories Not Appearing in Expected Order

1. **Check category names:** Ensure the names in `category_order` match actual category names
2. **Check spelling:** Category names are case-sensitive
3. **Try plural forms:** If "Employee" doesn't work, try "Employees"
4. **Check data:** Verify categories exist in the actual investment data

### Columns Not Hiding

1. **Check parameter syntax:** Use `show_quantity_actual: false` (not `"false"` in the metadata hash)
2. **Verify turbo frame reload:** Changes may require page refresh
3. **Inspect element:** Check if `style="display: none;"` is applied to table headers/cells

### Order String Not Parsing

1. **Remove spaces after commas:** Use `"Self,Employee,Other"` not `"Self, Employee, Other"`
2. **Use quotes correctly:** In Ruby hash format: `{category_order: 'Self,Employee'}`
3. **Check URL encoding:** In URLs, commas should work but may need encoding in some cases

## Related Features

This implementation follows the same pattern as other metadata-driven features:
- `show_currency_filter` for currency dropdown visibility (in other widgets)
- `tabs` for portfolio report section filtering
- Column visibility controls

# Cap Table Category Ordering - Visual Examples

## Before (Default Ordering - By Quantity)

With default settings or `metadata = "{}"`:

```
Particulars          | % stake fully diluted |
                     | Seed  | Series A | Series B |
---------------------+---------+----------+----------+
Lead Investors >     | 0.0%  | 50.0%    | 45.0%    |  ← Highest total
Founders >           | 85.0% | 35.0%    | 30.0%    |  ← Second highest
Employees >          | 10.0% | 10.0%    | 15.0%    |  ← Third
Others >             | 5.0%  | 5.0%     | 10.0%    |  ← Lowest
---------------------+---------+----------+----------+
Total                | 100.0%| 100.0%   | 100.0%   |
```

Categories are automatically sorted by their total ownership stake (descending).

---

## After (Custom Ordering - Founders First)

With `metadata = "{category_order: 'Self,Employee,Other,Lead Investor'}"`:

```
Particulars          | % stake fully diluted |
                     | Seed  | Series A | Series B |
---------------------+---------+----------+----------+
Founders >           | 85.0% | 35.0%    | 30.0%    |  ← 1st (custom order)
Employees >          | 10.0% | 10.0%    | 15.0%    |  ← 2nd (custom order)
Others >             | 5.0%  | 5.0%     | 10.0%    |  ← 3rd (custom order)
Lead Investors >     | 0.0%  | 50.0%    | 45.0%    |  ← 4th (custom order)
---------------------+---------+----------+----------+
Total                | 100.0%| 100.0%   | 100.0%   |
```

Categories follow your specified order regardless of ownership percentage.

---

## Example: Investor-Focused View

With `metadata = "{category_order: 'Lead Investor,Other'}"`:

```
Particulars          | % stake fully diluted |
                     | Seed  | Series A | Series B |
---------------------+---------+----------+----------+
Lead Investors >     | 0.0%  | 50.0%    | 45.0%    |  ← 1st (in custom list)
Others >             | 5.0%  | 5.0%     | 10.0%    |  ← 2nd (in custom list)
Founders >           | 85.0% | 35.0%    | 30.0%    |  ← Auto-sorted by quantity
Employees >          | 10.0% | 10.0%    | 15.0%    |  ← Auto-sorted by quantity
---------------------+---------+----------+----------+
Total                | 100.0%| 100.0%   | 100.0%   |
```

Listed categories appear first in order, unlisted categories follow sorted by quantity.

---

## Example: Using Display Names

With `metadata = "{category_order: 'Founders,Employees,Others,Demo Fund'}"`:

The system automatically maps:
- "Founders" → "Self" category
- "Employees" → "Employee" category
- "Others" → "Other" category
- "Demo Fund" → "Lead Investor" category

Result (same as founders-first example):
```
Particulars          | % stake fully diluted |
                     | Seed  | Series A | Series B |
---------------------+---------+----------+----------+
Startup Inc >        | 85.0% | 35.0%    | 30.0%    |  ← Founders (Self)
Employees >          | 10.0% | 10.0%    | 15.0%    |  ← Employees
Others >             | 5.0%  | 5.0%     | 10.0%    |  ← Others
Demo Fund >          | 0.0%  | 50.0%    | 45.0%    |  ← Demo Fund (Lead Investor)
---------------------+---------+----------+----------+
Total                | 100.0%| 100.0%   | 100.0%   |
```

---

## Combined: Custom Order + Hidden Columns

With metadata:
```ruby
{
  category_order: 'Self,Employee,Other,Lead Investor',
  show_quantity_actual: false,
  show_quantity_diluted: false
}
```

Result:
```
Particulars          | % stake fully diluted |
                     | Seed  | Series A | Series B |
---------------------+---------+----------+----------+
Founders >           | 85.0% | 35.0%    | 30.0%    |
Employees >          | 10.0% | 10.0%    | 15.0%    |
Others >             | 5.0%  | 5.0%     | 10.0%    |
Lead Investors >     | 0.0%  | 50.0%    | 45.0%    |
---------------------+---------+----------+----------+
Total                | 100.0%| 100.0%   | 100.0%   |
```

Note: "Quantity actual" and "Quantity- fully diluted" columns are hidden!

---

## Real-World Use Cases

### Use Case 1: Board Report
**Goal:** Show founders' ownership prominently
```ruby
{category_order: 'Self,Lead Investor,Employee,Other'}
```

### Use Case 2: Investor Pitch Deck
**Goal:** Emphasize external investment
```ruby
{category_order: 'Lead Investor,Other,Self,Employee'}
```

### Use Case 3: ESOP Report
**Goal:** Focus on employee ownership
```ruby
{category_order: 'Employee,Self,Lead Investor,Other'}
```

### Use Case 4: Clean Executive Summary
**Goal:** Hide detailed quantities, show only percentages
```ruby
{
  category_order: 'Self,Employee,Lead Investor,Other',
  show_quantity_actual: false,
  show_quantity_diluted: false
}
```

---

## Configuration Quick Reference

| What You Want | Metadata Configuration |
|---------------|----------------------|
| Founders first | `{category_order: 'Self,Employee,Other,Lead Investor'}` |
| Investors first | `{category_order: 'Lead Investor,Other,Self,Employee'}` |
| Alphabetical | `{category_order: 'Employee,Lead Investor,Other,Self'}` |
| Hide quantities | `{show_quantity_actual: false, show_quantity_diluted: false}` |
| Custom + clean | `{category_order: 'Self,Employee', show_quantity_diluted: false}` |
| Default (quantity-based) | `{}` or omit metadata |

---

## Tips

1. **Start simple:** Use exact category names first ("Self", "Employee", etc.)
2. **Test with plurals:** If it doesn't work, try "Employees" instead of "Employee"
3. **Partial is OK:** You don't need to list all categories
4. **Case matters:** Use proper capitalization
5. **No spaces:** After commas in the list (or trim them)
6. **Combine features:** Mix ordering with column visibility for powerful customization

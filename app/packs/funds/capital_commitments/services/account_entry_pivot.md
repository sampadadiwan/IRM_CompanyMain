# Account Entry Pivot Pagination & Performance

This document explains the performance-optimized pagination strategy implemented in the `AccountEntryPivot` service.

## The Problem
Pivot tables for account entries often involve thousands of records. Standard Rails pagination doesn't work well because a "page" in a pivot table refers to a subset of **Rows** (Commitments/Parents), while each row might aggregate hundreds of individual **Account Entries**.

Initial attempts to paginate caused:
1.  **Memory Spikes**: Loading all `AccountEntry` ActiveRecord objects into the Ruby heap (up to 1GB per request).
2.  **Inconsistent Layouts**: Changing pages would cause columns (Dates/Groups) to disappear if they didn't have data on the current page.
3.  **Redundant Queries**: Multiple iterations over the database relation.

## The Solution
The current implementation uses a **Metadata-First** approach to pagination at the database level.

### 1. Row Identification (Metadata Phase)
Instead of loading objects, we use a minimal `distinct.pluck` to identify unique row keys (Commitments and optionally Parents) for the entire filtered set.
```ruby
all_rows = @account_entries.distinct.pluck(:commitment_name, :capital_commitment_id, ...)
```
This identifies exactly how many "pivot rows" exist without loading the entries themselves.

### 2. Header Stability (Metadata Phase)
To ensure the table headers (Dates and Groups) remain identical across every page, we fetch the unique combinations of the grouping field and reporting dates for the **entire** dataset.
```ruby
group_dates = @account_entries.distinct.pluck(@group_by_field, :reporting_date)
```
This allows the view to render consistent columns even if the rows on the current page have no data for some dates.

### 3. Paginated Data Fetching (Content Phase)
Once `Pagy` determines the offset for the current page, we fire a targeted `pluck` query for only the rows being displayed (typically 20).
```ruby
paginated_query = @account_entries.where(specific_rows_conditions).pluck(...)
```
Crucially, we use `pluck` here too, which bypasses ActiveRecord object instantiation entirely, saving significant memory.

## Key Performance Rules
1.  **Never instantiate ActiveRecord objects**: Always use `pluck` to get raw data for pivot calculations.
2.  **Separate Metadata from Content**: Fetch row/column structure first, then fetch detailed data only for the visible slice.
3.  **Bypass Joins**: By using columns like `commitment_name` and `parent_name` directly from the `account_entries` table (which are populated via denormalization or calculations), we avoid heavy JOINs during the pivot build.

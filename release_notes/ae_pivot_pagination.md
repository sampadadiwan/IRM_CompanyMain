# PR: Implement Pagination and Memory Optimization for Account Entry Pivot Table

## Overview
Implemented `Pagy`-based pagination and significant memory optimizations for the Account Entry pivot table to handle large datasets efficiently.

## Motivation
The Account Entry pivot table was loading all records into memory, leading to high memory usage and slow performance when dealing with a large number of account entries. Pagination was needed to improve usability and system stability.

## What Changed
- **`ApplicationController`**: Added `log_memory_delta` helper to track memory usage in development.
- **`AccountEntriesController`**: Enabled `log_memory_delta` for better performance monitoring.
- **`AccountEntryList` Service**: Updated to pass pagination parameters (`page`, `per_page`) to the pivot service.
- **`AccountEntryPivot` Service**:
    - Refactored to use `Pagy` for pagination.
    - Optimized database queries using `pluck` and `except(:includes, :order)` to avoid loading full ActiveRecord objects.
    - Implemented targeted querying for only the current page's data.
    - Reduced memory footprint by using raw data and minimal `OpenStruct` objects instead of heavy model instances.
- **`_pivot.html.erb` View**: Added pagination navigation links using `pagy_bootstrap_nav`.
- **`select2.scss`**: Minor adjustment to padding (commented out).
- **`database.yml`**: Updated development credentials.

## Refactoring / Behavior Changes
- Shifted from an all-in-memory aggregation to a paginated, database-aware aggregation strategy in `AccountEntryPivot`.
- The pivot table now only renders a subset of rows per page, drastically reducing the DOM size and browser rendering time for large funds.

## Testing
- Manual testing in development environment to verify pagination and memory delta logs.
- Verified that chart data remains consistent with the filtered/paginated view (where applicable).

## Impact
- **Performance**: Significant reduction in memory consumption on the server.
- **Usability**: Faster page loads and a more responsive UI for account entry management.

## Review Focus
- Check the `AccountEntryPivot` pagination logic, specifically the row identification and targeted querying.
- Ensure the `OpenStruct` fallback in the service correctly satisfies the view's requirements without introducing regressions.

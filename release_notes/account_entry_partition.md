**Overview**: This PR introduces database-native partitioning for the `account_entries` table in MySQL 8 to improve performance, simplify archiving, and optimize query costs.

**Motivation**: The `account_entries` table has grown significantly (beyond 2M rows), leading to performance concerns and increased query costs. Partitioning by `reporting_date` addresses these issues by allowing MySQL to scan only relevant data partitions for reporting-driven queries and simplifying the archiving of old data.

**What Changed**:
*   **Database Partitioning**: Implemented MySQL 8 RANGE partitioning by `reporting_date` for the `account_entries` table. Detailed documentation for this partitioning strategy is provided in `app/packs/funds/capital_commitments/models/account_entry_partitioning.md`.
*   **Controller Enhancements (`app/packs/funds/capital_commitments/controllers/account_entries_controller.rb`)**:
    *   The `fetch_rows` action now automatically applies a `reporting_date_gt` filter (last 6 months) to Ransack queries if no `reporting_date` filter is explicitly provided, ensuring efficient partition pruning.
    *   The `set_account_entry` method has been updated to utilize `params[:reporting_date]` when present, allowing for more efficient `AccountEntry` lookups by leveraging the partition key.
*   **Model Update (`app/packs/funds/capital_commitments/models/account_entry.rb`)**: Set `self.primary_key = :id` to align with how Rails interacts with the partitioned table structure.
*   **View Updates**:
    *   `app/packs/funds/capital_commitments/views/account_entries/_account_entry.html.erb`: Modified the "show" link for account entries to include `reporting_date` in the URL, facilitating efficient retrieval.
    *   `app/packs/funds/capital_commitments/views/capital_commitments/_details.html.erb`: The `turbo_frame_tag` for `account_entries_frame` now includes a default `reporting_date` filter (last 6 months) in its `src` URL to optimize initial data loading.
*   **Cleanup**: Removed the `create_custom_fields` step from `app/packs/core/entities/services/import_exchange_rate.rb` and `app/packs/misc/form_custom_fields/services/import_form_custom_fields.rb` as these models do not have custom fields.

**Refactoring / Behavior Changes**:
*   **Architectural Shift**: The `account_entries` table is now physically partitioned in the database, which is transparent to the Rails application but requires careful consideration for query optimization.
*   **Query Optimization**: Queries on `account_entries` that include `reporting_date` filters will now benefit significantly from partition pruning, leading to faster execution. Queries without `reporting_date` will still function but may perform full partition scans.
*   **Data Retrieval**: Direct `AccountEntry.find(id)` calls are now less efficient without `reporting_date`. The controller has been updated to handle this by attempting to use `reporting_date` if available.

**Testing**:
*   Manual testing was performed to verify that `account_entries` are correctly displayed and filtered in the UI.
*   Tested `show` and `fetch_rows` actions in `AccountEntriesController` to ensure correct data retrieval with and without `reporting_date` parameters.
*   Verified that new account entries are created and stored correctly within the partitioned table.

**Impact**:
*   **Performance**: Expected significant performance improvements for `account_entries` queries that filter by `reporting_date`.
*   **Maintainability**: Simplified archiving and deletion of old `account_entries` data by dropping entire partitions.
*   **Compatibility**: No breaking changes are expected for existing functionalities, but developers should be aware of the new partitioning strategy for optimal query writing.
*   **Database Schema**: The `account_entries` table now has a composite primary key `(id, reporting_date)` and does not support foreign keys.

**Review Focus**:
*   **Partitioning Strategy**: Review the `app/packs/funds/capital_commitments/models/account_entry_partitioning.md` documentation for accuracy and completeness.
*   **Controller Logic**: Pay close attention to the changes in `AccountEntriesController#fetch_rows` and `AccountEntriesController#set_account_entry` to ensure correct and efficient handling of `reporting_date` for partitioned queries.
*   **View Updates**: Verify that all links and data loading mechanisms for `account_entries` correctly pass `reporting_date` where appropriate.
*   **`self.primary_key = :id`**: Confirm that setting `self.primary_key = :id` in `AccountEntry` model is the correct approach for Rails interaction with the partitioned table.
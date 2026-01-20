# PR: Optimization of Account Entry Allocation Process

1. **Overview**: This PR introduces significant performance optimizations to the `AccountEntryAllocation` services by implementing centralized commitment loading, query caching, and memoization.

2. **Motivation**: The previous implementation suffered from $O(N)$ database queries (where $N$ is the number of formulas), specifically regarding capital commitments, exchange rates, and master fund account entries, leading to slow allocation runs.

3. **What Changed**:
    - **Centralized Commitment Loading**: Refactored `RunFormulas` to load capital commitments once per allocation run and share them via the context (`ctx[:commitments]`).
    - **Query Caching**:
        - Cached `portfolio_companies` in `AllocateForPortfolioCompany`.
        - Cached `exchange_rates` and `master_fund_account_entries` in `AllocateMasterFundAccountEntries`.
    - **Refactored `RunFormulas`**: Extracted formula execution and entry deletion into private methods for better readability and maintainability.
    - **Optimization Documentation**: Added `optimization_suggestions.md` documenting further potential improvements.
    - **Database Config**: Restored development database passwords in `config/database.yml`.
    - **Bulk Insert Improvements**: Streamlined `BulkInsertData` to avoid redundant record counts and simplified insertion logic.

4. **Refactoring / Behavior Changes**:
    - Shifted from per-formula commitment fetching to a centralized "step" in the `RunFormulas` operation.
    - Removed redundant transaction wraps in `AllocationBaseOperation#safe_eval` to improve performance during formula evaluation.
    - Updated `BulkInsertData` to rely on successful insertion counts rather than re-querying the database for validation.

5. **Testing**:
    - Manual verification of allocation runs on large datasets to ensure data integrity and performance gains.
    - Verified that `ctx[:commitments]` is correctly utilized across all allocation sub-services.

6. **Impact**:
    - Reduced database load during allocation runs.
    - Significant reduction in execution time for funds with a high number of formulas and commitments.
    - Improved code maintainability through extraction of logic into private methods.

7. **Review Focus**:
    - Ensure `ctx[:commitments]` pre-loading handles all necessary scopes and inclusions used by different formulas.
    - Verify the logic in `BulkInsertData` regarding the removal of redundant count queries.
    - Review the new `optimization_suggestions.md` for any immediate actionable items.

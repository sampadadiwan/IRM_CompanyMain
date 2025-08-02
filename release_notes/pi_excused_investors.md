# Release Notes: pi_excused_investors

1.  **Overview**: This branch introduces the ability to mark specific folios as "excused" for portfolio investments, alongside several refactorings and updates to user authentication and entity management.

2.  **Motivation**: The primary motivation is to provide granular control over which folios are included or excluded from a portfolio investment, enhancing flexibility in financial tracking. Additionally, several improvements were made to user and entity lifecycle management, and general code quality.

3.  **What Changed**:
    *   **Excused Folios Feature:**
        *   Added `excused_folio_ids` attribute to `PortfolioInvestment` model to store a list of excused folio IDs.
        *   Introduced `normalize_excused_folio_ids` callback to ensure data integrity for the new attribute.
        *   Added `with_all_excused_folio_ids` scope for querying portfolio investments based on excused folios.
        *   Updated `PortfolioInvestmentsController` to permit `excused_folio_ids` and `CapitalCommitmentsController` to filter by `capital_commitment_ids`.
        *   Enhanced `_form.html.erb` and `_details.html.erb` for `PortfolioInvestment` to allow selection and display of excused folios.
    *   **User & Entity Management:**
        *   `Entity` model now deactivates associated employees (`active: false`) when the entity itself is disabled.
        *   `User#active_for_authentication?` no longer checks the associated entity's active status, allowing users to be active independently of their primary entity.
    *   **Authorization & Validation:**
        *   `Investor` policy now allows investor advisors to view investor details if they have general `show?` access.
        *   Updated `Valuation` uniqueness validation to use modern Rails syntax.
    *   **Code Refinements:**
        *   Refactored `InvestorKycUpserter` to consolidate `OpenStruct` return statements.
        *   Added memoization to `map_custom_fields` and `custom_calculations` in `WithCustomField` concern for performance.
        *   Minor refactoring in `PortfolioInvestmentCreate` service for clarity.

4.  **Refactoring / Behavior Changes**:
    *   The `User#active_for_authentication?` method's behavior has changed; a user's active status is now independent of their associated entity's active status. This means users can remain active even if their primary entity is disabled.
    *   When an `Entity` is disabled, all its associated `employees` will now be automatically deactivated.
    *   The `Investor` policy has been relaxed to allow `investor_advisor` roles to view investor details if they have a general `show?` permission, providing more flexible access.

5.  **Testing**:
    *   A test step in `features/step_definitions/investor.rb` related to checking investor entity name on the details page was commented out, likely to accommodate the changes in user/entity active status or investor policy.

6.  **Impact**:
    *   **Data Integrity:** The `excused_folio_ids` feature introduces new data storage and validation for portfolio investments.
    *   **User Authentication:** Users might remain active even if their primary entity is disabled, which could affect existing workflows that rely on entity status for user access.
    *   **Performance:** Memoization in `WithCustomField` concern should provide minor performance improvements for custom field lookups.
    *   **UI/UX:** New fields and tabs are introduced for portfolio investments, requiring user familiarity with the new "Excused Folios" functionality.

7.  **Review Focus**:
    *   The implications of `User#active_for_authentication?` no longer depending on `entity.active`.
    *   The `deactivate_employees` callback on `Entity` and its potential side effects.
    *   The `excused_folio_ids` implementation, especially data handling, UI integration, and its interaction with existing investment logic.
    *   The updated `Investor` policy and its impact on access control.
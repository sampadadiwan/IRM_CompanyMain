**Release Notes for `investor_advisor_auto_switch`**

1.  **Overview**: This release introduces the ability for Investor Advisors to automatically switch between investor entities and adds a new feature to mark capital distribution payments as completed.

2.  **Motivation**: The primary motivation for these changes is to enhance the user experience for Investor Advisors by providing a seamless way to manage multiple investor entities without manual switching, and to streamline the process of marking capital distribution payments as complete, improving workflow efficiency and communication with investors.

3.  **What Changed**:
    *   **Investor Advisor Auto-Switch**:
        *   Added a `before_action` in `WithAuthentication` to automatically switch the advisor context based on `investor_advisor_id` in URL parameters for users with the `investor_advisor` role.
        *   Introduced a new `investor_advisor_id` helper method in `BaseNotifier` to correctly pass the advisor ID in email notification parameters.
        *   Modified various mailer views (`investor_kyc_mailer`, `capital_distribution_payments_mailer`, `capital_remittance_mailer`, `investment_opportunity_mailer`, `expression_of_interest_mailer`) to include `investor_advisor_id` in generated URLs, ensuring context persistence.
        *   Optimized `_personas.html.erb` to eager load `InvestorAdvisor` entities, reducing N+1 queries.
        *   Refactored `Investor` model policy check for clarity.
    *   **Mark Capital Distribution Payments Completed**:
        *   Added a new `payments_completed` action to `CapitalDistributionPaymentsController` to mark a payment as complete and trigger updates.
        *   Introduced a `payments_completed?` policy method in `CapitalDistributionPaymentPolicy`.
        *   Added a "Mark Payment Completed" button to the `capital_distribution_payments/show.html.erb` view.
        *   Updated `FundsController` and `FundsHelper` to support `CapitalDistributionPayment` in the email list generation.
        *   Added a new route for `payments_completed` in `config/routes/fund.rb`.

4.  **Refactoring / Behavior Changes**:
    *   The `Investor` model's policy check for `permissioned_investor_advisor?` was slightly refactored for readability, but its core behavior remains unchanged.
    *   The `show_email_list` functionality in `FundsController` and `FundsHelper` now explicitly supports `CapitalDistributionPayment` models, ensuring correct email list generation for this type of record.
    *   Mailer `before_action` callbacks were introduced to set instance variables, improving code organization within mailers.

5.  **Testing**:
    *   Unit tests for the new `switch_advisor` functionality and `payments_completed` action should be verified.
    *   Integration tests should confirm that the `investor_advisor_id` is correctly passed and maintained across different application flows, especially when navigating from email links.
    *   Manual testing should involve:
        *   Logging in as an Investor Advisor and verifying the automatic switching behavior when `investor_advisor_id` is present in the URL.
        *   Testing all affected email links to ensure they correctly redirect with the `investor_advisor_id` parameter.
        *   Verifying the "Mark Payment Completed" functionality, including the notification trigger and the status update.
        *   Checking the email list generation for Capital Distribution Payments.

6.  **Impact**:
    *   **User Experience**: Improved navigation and context management for Investor Advisors.
    *   **Workflow Efficiency**: Streamlined process for marking capital distribution payments as complete.
    *   **Performance**: Minor optimization in `_personas.html.erb` due to eager loading.
    *   **Compatibility**: No known breaking changes.

7.  **Review Focus**:
    *   Ensure the `switch_advisor` logic correctly handles all edge cases, especially authorization and data consistency.
    *   Verify that `investor_advisor_id` is consistently and correctly appended to all relevant URLs in mailer views.
    *   Confirm the `payments_completed` action's robustness, including error handling and notification triggers.
    *   Review the `email_list_for_model` helper for `CapitalDistributionPayment` to ensure accurate recipient identification.
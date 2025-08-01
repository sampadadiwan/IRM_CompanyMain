**Overview**: This PR integrates CKYC and KRA services to automate investor KYC verification, enhancing efficiency and compliance.

**Motivation**: This change was made to streamline the investor onboarding process by automating KYC data fetching and verification, reducing manual effort, improving data accuracy, and ensuring adherence to regulatory requirements.

**What Changed**:

*   **CKYC/KRA Integration**: Implemented functionality to search, fetch, and assign CKYC and KRA data to investor KYC records.
*   **OTP Verification**: Introduced an OTP-based flow for secure CKYC data download.
*   **Dynamic KYC Forms**: Modified investor KYC forms to adapt based on CKYC/KRA enablement and existing KYC data.
*   **Data Assignment & Refetch**: Added capabilities to select and pre-populate KYC fields with fetched CKYC/KRA data, and to re-fetch updated data.
*   **Permissions Shift**: Moved CKYC and KRA enablement flags from [`EntitySetting`](app/packs/core/entities/models/entity_setting.rb) to [`Entity`](app/packs/core/entities/models/entity.rb) permissions, with a new validation requiring an FI code when these features are active.
*   **New Stimulus Controller**: Created [`app/javascript/controllers/resend_otp_controller.js`](app/javascript/controllers/resend_otp_controller.js) to manage OTP resend cooldown.
*   **New Views**: Added new views and partials for the CKYC/KRA workflow, including:
    *   [`app/packs/core/investor_kycs/views/investor_kycs/_initial_form.html.erb`](app/packs/core/investor_kycs/views/investor_kycs/_initial_form.html.erb)
    *   [`app/packs/core/investor_kycs/views/investor_kycs/compare_ckyc_kra.html.erb`](app/packs/core/investor_kycs/views/investor_kycs/compare_ckyc_kra.html.erb)
    *   [`app/packs/core/investor_kycs/views/kyc_datas/enter_ckyc_otp.html.erb`](app/packs/core/investor_kycs/views/kyc_datas/enter_ckyc_otp.html.erb)
    *   [`app/packs/core/investor_kycs/views/kyc_datas/_form.html.erb`](app/packs/core/investor_kycs/views/kyc_datas/_form.html.erb)
    *   [`app/packs/core/investor_kycs/views/kyc_datas/_kyc_data.html.erb`](app/packs/core/investor_kycs/views/kyc_datas/_kyc_data.html.erb)
    *   [`app/packs/core/investor_kycs/views/kyc_datas/_show.html.erb`](app/packs/core/investor_kycs/views/kyc_datas/_show.html.erb)
*   **Route Enhancements**: Updated [`config/routes/core.rb`](config/routes/core.rb) with new routes for CKYC/KRA actions.
*   **Localization**: Added new translation keys in [`config/locales/en.yml`](config/locales/en.yml) and [`config/locales/ja.yml`](config/locales/ja.yml).

**Refactoring / Behavior Changes**:

*   The management of CKYC and KRA enablement has been centralized under the `Entity` model's permissions, removing redundant flags from `EntitySetting`.
*   The investor KYC creation/edit flow now conditionally includes an intermediate step for CKYC/KRA data interaction, providing a more guided user experience.

**Testing**:

*   Comprehensive Cucumber tests have been added in [`features/misc/ckyc_kra.feature`](features/misc/ckyc_kra.feature) to validate:
    *   Successful CKYC and KRA data fetching and assignment.
    *   Error handling and input validations for CKYC/KRA.
    *   User flows for both CKYC and KRA enabled scenarios.
    *   Functionality for editing and re-fetching KYC data.
    *   Investor-initiated KYC completion process.
*   API calls to external CKYC/KRA services are stubbed in [`features/step_definitions/kyc_data.rb`](features/step_definitions/kyc_data.rb) to ensure consistent and isolated test execution.

**Impact**:

*   **Positive**: Significantly improves the efficiency and accuracy of investor KYC onboarding, reducing manual data entry and enhancing regulatory compliance.
*   **Negative**: Introduces new external API dependencies for CKYC/KRA services. Requires careful handling of sensitive investor data to maintain security and privacy.

**Review Focus**:

*   **Stimulus Controller**: Review [`app/javascript/controllers/resend_otp_controller.js`](app/javascript/controllers/resend_otp_controller.js) for correct OTP resend logic and cooldown implementation.
*   **Controller & Views**: Examine [`InvestorKycsController`](app/packs/core/investor_kycs/controllers/investor_kycs_controller.rb) and associated views for proper conditional rendering, data flow, and user experience during CKYC/KRA interactions.
*   **Permissions & Validations**: Verify the new permissions and validations in [`app/packs/core/entities/models/concerns/entity_enabled.rb`](app/packs/core/entities/models/concerns/entity_enabled.rb) and [`app/packs/core/entities/models/entity.rb`](app/packs/core/entities/models/entity.rb).
*   **Test Coverage**: Ensure the new Cucumber feature and step definitions provide adequate test coverage for all CKYC/KRA scenarios, including edge cases.
*   **Security**: Pay close attention to how sensitive data (PAN, OTP, KYC details) is handled throughout the application, ensuring adherence to security best practices.
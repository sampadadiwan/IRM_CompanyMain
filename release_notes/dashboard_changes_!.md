# PR: Dashboard Enhancements and AI Agent Orchestration

## Overview
This PR introduces significant enhancements to the fund dashboard, including new widgets, improved portfolio calculations with tracking currency support, and a foundational design for AI agent orchestration. It also refactors scenario investment forms and adds comprehensive Cucumber tests for new functionalities.

## Motivation
The changes were made to:
*   Enhance the fund dashboard with more insightful widgets, providing better data visualization for users.
*   Improve the accuracy and flexibility of portfolio calculations by incorporating tracking currency support, addressing a critical need for multi-currency funds.
*   Lay the groundwork for integrating Python AI agents, enabling future advanced analytical capabilities.
*   Streamline the creation and management of portfolio scenarios and investments.
*   Improve the robustness of the application through additional test coverage for new features.

## What Changed

*   **AI Agent Orchestration Design**: A new design document (`app/packs/ai/calling_python_agents.md`) outlines the integration of Rails with FastAPI for AI agent execution, including asynchronous processing, real-time progress updates, and robust error handling.
*   **Dashboard Widgets**:
    *   Added "Embedded Document" widget (`app/packs/funds/funds/views/funds/widgets/_embedded_doc.html.erb`) to allow embedding documents directly into fund dashboards.
    *   New `DashboardWidget` entries in `app/packs/core/base/models/dashboard_widget.rb` for "Embedded Document" and "Fund Portfolio Stats".
*   **Tracking Currency in Portfolio Calculations**:
    *   The `tracking_exchange_rate` method in `app/packs/core/base/models/concerns/with_exchange_rate.rb` now accepts an optional `exchange_rate_date` for more precise exchange rate lookups.
    *   `gross_portfolio_irr`, `portfolio_company_irr`, and `api_irr` methods in `app/packs/funds/funds/services/fund_portfolio_calcs.rb` now support an optional `use_tracking_currency` parameter, enabling IRR calculations in the fund's tracking currency.
    *   `PortfolioInvestment` model (`app/packs/funds/portfolios/models/portfolio_investment.rb`) now includes `tracking_amount_cents` and `tracking_fmv_cents` for monetized tracking currency values.
*   **Portfolio Scenario and Investment Improvements**:
    *   Removed `WithCustomField` concern from `PortfolioScenario` and `ScenarioInvestment` models (`app/packs/funds/portfolios/models/portfolio_scenario.rb`, `app/packs/funds/portfolios/models/scenario_investment.rb`).
    *   The `investment_instruments_controller.rb` now sets `@investment_type`.
    *   Updated `_form.html.erb` for `scenario_investments` to correctly handle `investment_type` and improve instrument selection for new records.
    *   New turbo stream (`app/packs/funds/portfolios/views/scenario_investments/new.turbo_stream.erb`) for creating new scenario investments.
*   **Grid View Preferences**: `GridViewPreferencesController` (`app/packs/misc/grid_view_preferences/controller/grid_view_preferences_controller.rb`) now dynamically includes `ADDITIONAL_COLUMNS` from models if defined, enhancing grid customization.
*   **Document Routes**: Added a `show_file` route for documents in `config/routes/core.rb`.
*   **Model Enhancements**:
    *   `Fund` model (`app/packs/funds/funds/models/fund.rb`) now includes `STANDARD_COLUMNS`.
    *   `FundRatio` model (`app/packs/funds/funds/models/fund_ratio.rb`) now includes `ADDITIONAL_COLUMNS_FROM`.
    *   `PortfolioInvestment` model (`app/packs/funds/portfolios/models/portfolio_investment.rb`) now includes `ADDITIONAL_COLUMNS` and `ADDITIONAL_COLUMNS_FROM`.
*   **Cucumber Tests**: New and updated Cucumber scenarios in `features/fund/portfolio.feature` and `features/step_definitions/portfolio.rb` to cover portfolio scenario and investment creation, as well as import functionalities.

## Refactoring / Behavior Changes
*   The `WithExchangeRate` concern now allows for specifying a date when fetching exchange rates, providing more accurate historical calculations.
*   IRR calculations in `FundPortfolioCalcs` can now be performed using the tracking currency, which changes the numerical output of these calculations when `use_tracking_currency` is enabled.
*   The grid view preferences now automatically pick up additional columns defined in models, leading to more flexible and configurable data tables.
*   The `PortfolioScenario` and `ScenarioInvestment` models no longer include `WithCustomField`, simplifying their structure.

## Testing
*   **Cucumber Tests**: Extensive new Cucumber scenarios have been added for:
    *   Creating and updating portfolio scenarios.
    *   Creating new scenario investments, including validation error handling.
    *   Importing portfolio investments and verifying their creation and computed values.
    *   Verifying PI details on the details page.
*   Minor adjustments to existing step definitions in `features/step_definitions/fund_ratio.rb` and `features/step_definitions/investor_kyc.rb`.
*   Removed `binding.pry` statements from step definitions.

## Impact
*   **Performance**: The changes to IRR calculations might have a minor impact on performance due to additional exchange rate lookups when `use_tracking_currency` is enabled. This is expected to be negligible for typical use cases.
*   **Compatibility**: No known backward compatibility issues.
*   **User Experience**: Users will benefit from enhanced dashboard widgets, more accurate multi-currency portfolio calculations, and a more streamlined experience for managing scenarios and investments.
*   **Developer Experience**: The AI agent orchestration design provides a clear path for future AI integrations. The dynamic `ADDITIONAL_COLUMNS` feature simplifies grid view customization.

## Review Focus
Reviewers should pay close attention to:
*   The implementation of `use_tracking_currency` in `FundPortfolioCalcs` to ensure correct currency conversion and calculation logic.
*   The new `_embedded_doc.html.erb` partial and its integration into the dashboard.
*   The changes in `GridViewPreferencesController` to ensure `ADDITIONAL_COLUMNS` are correctly picked up and displayed.
*   The new Cucumber scenarios and step definitions to ensure comprehensive test coverage for the new features.
*   The `calling_python_agents.md` document for clarity and completeness of the AI agent orchestration design.
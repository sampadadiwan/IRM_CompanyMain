# Release Note: AI-Powered Fund Formula Descriptions

**Overview**: This release introduces AI-powered explanations for fund allocation formulas, enhancing clarity and understanding for non-technical users.

**Motivation**: To provide clear, plain-language explanations of complex fund allocation formulas, making them more accessible to fund managers and other non-technical team members, and to automate the process of generating and updating these descriptions.

**What Changed**:
*   **New AI Services**:
    *   [`FundFormulaExplainer`](app/packs/ai/fund_formula_explainer.rb): Generates human-readable explanations for fund formulas using a Large Language Model (LLM).
    *   [`FundFormulaVariableService`](app/packs/ai/fund_formula_variable_service.rb): Manages and provides variable mappings for fund formulas from a new YAML configuration.
    *   [`LlmInitializer`](app/packs/ai/llm_initializer.rb) and [`LlmService`](app/packs/ai/llm_service.rb): Centralized modules for initializing and interacting with various LLM providers (Gemini, OpenAI, Anthropic).
*   **New Background Jobs**:
    *   [`GenerateAiDescriptionsJob`](app/packs/funds/funds/jobs/generate_ai_descriptions_job.rb): A job to asynchronously generate and update AI descriptions for all fund formulas of a given fund.
    *   [`UpdateFundFormulaVariableMapJob`](app/packs/funds/funds/jobs/update_fund_formula_variable_map_job.rb): A job to automatically update the `config/fund_formula_variable_map.yml` file by analyzing Ruby code using an LLM.
*   **Fund Formula Enhancements**:
    *   [`FundFormula`](app/packs/funds/funds/models/fund_formula.rb) model now includes an `ai_description` field and a scope to find formulas without AI descriptions.
    *   [`FundFormulasController`](app/packs/funds/funds/controllers/fund_formulas_controller.rb) includes a new `generate_ai_descriptions` action to trigger the background job.
    *   [`FundFormulaPolicy`](app/packs/funds/funds/policies/fund_formula_policy.rb) updated to include authorization for generating AI descriptions.
*   **UI Updates**:
    *   A "Generate AI Descriptions" button has been added to the fund formulas index page ([`_index.html.erb`](app/packs/funds/funds/views/fund_formulas/_index.html.erb)).
    *   The `ai_description` field is now displayed in the fund formula show view ([`show.html.erb`](app/packs/funds/funds/views/fund_formulas/show.html.erb)) and as a disabled field in the form ([`_form.html.erb`](app/packs/funds/funds/views/fund_formulas/_form.html.erb)).
*   **Configuration**:
    *   A new `config/fund_formula_variable_map.yml` file has been added to define variables used in fund formulas.
    *   New route `generate_ai_descriptions` added to `config/routes/fund.rb`.

**Refactoring / Behavior Changes**:
*   Introduced a modular AI integration layer using `LlmInitializer` and `LlmService` for consistent LLM interactions.
*   Automated the process of generating formula explanations and updating variable mappings, reducing manual effort.
*   The `ai_description` field is read-only in the UI, indicating it's AI-generated.

**Testing**:
*   The diff does not explicitly show test file changes, but the new jobs and services would require unit and integration tests to ensure correctness and reliability of AI-generated content and variable mapping updates.

**Impact**:
*   **Improved User Understanding**: Non-technical users will have clearer explanations of complex financial formulas.
*   **Automation**: Reduces manual effort in documenting and explaining formulas.
*   **New Dependencies**: Introduces `langchain` gem and reliance on external LLM providers (Gemini, OpenAI, Anthropic).
*   **Configuration**: Requires `config/fund_formula_variable_map.yml` and environment variables for LLM API keys.

**Review Focus**:
*   Review the prompts used in `FundFormulaExplainer` and `UpdateFundFormulaVariableMapJob` for clarity, accuracy, and effectiveness in guiding the LLM.
*   Verify the variable mapping logic in `FundFormulaVariableService` to ensure all relevant variables are correctly identified and consolidated.
*   Assess the error handling and notification mechanisms in `GenerateAiDescriptionsJob`.
*   Confirm that sensitive API keys are handled securely via Rails credentials or environment variables.
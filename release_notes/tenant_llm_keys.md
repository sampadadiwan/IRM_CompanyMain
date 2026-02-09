# PR: Entity-Specific LLM Integration and Configuration

## Overview
This PR introduces the ability for individual entities (tenants) to configure their own LLM API keys (OpenAI, Gemini, Anthropic, OpenRouter) and default models, ensuring that AI-driven features use tenant-specific infrastructure.

## Motivation
To support multi-tenancy for AI features, allowing entities to provide their own API keys for cost management, security, and access to specific models while maintaining a fallback to global system credentials.

## What Changed
- **LLM Service Refactoring**: Updated `LlmService.ruby_llm_chat` to accept an `entity` and initialize `RubyLLM` with the entity's specific API keys and default model.
- **Entity Settings Dashboard**: Added fields for `openai_api_key`, `gemini_api_key`, `anthropic_api_key`, `openrouter_api_key`, and `default_llm_model` to the `EntitySettingDashboard`.
- **AI Service Integration**: Refactored 13+ AI service objects and jobs (e.g., `ChartAgentService`, `PortfolioReportAgent`, `SlideGeneratorService`) to pass the `entity` context to the `LlmService`.
- **Database Schema**:
    - Added API key and model columns to the `entity_settings` table.
    - Updated `db/schema.rb` and `db/schema_test.rb` to version `2026_02_08_090154`.
- **Documentation**: Added `docs/llm_configuration_guide.md` to explain how to set up tenant-specific keys.

## Refactoring / Behavior Changes
- **Contextual LLM Initialization**: Shifted from a global environment-based LLM configuration to a dynamic, context-aware initialization based on the current entity.
- **Writing Role Access**: Wrapped `AiChatSession` creation in `AiPortfolioReportsController` within an `ActiveRecord::Base.connected_to(role: :writing)` block to ensure correct database connection handling.

## Testing
- Verified that AI services correctly fall back to system credentials when entity keys are blank.
- Manual verification of the `EntitySetting` form in the admin dashboard.
- Updated `config/credentials/test.yml.enc` to support local test environments.

## Impact
- **Security**: Tenants can now use their own API keys, reducing reliance on shared system keys.
- **Customization**: Entities can choose their preferred LLM models independently.
- **Infrastructure**: Requires existing `EntitySetting` records to be updated via the admin dashboard if custom keys are desired.

## Review Focus
- Verify the `LlmService.ruby_llm_chat` fallback logic ensures system-wide defaults are used when entity settings are missing.
- Ensure the new `entity_settings` columns are correctly handled in the Administrate dashboard.
- Confirm that the `writing` role connection in `AiPortfolioReportsController` follows project standards for database role management.

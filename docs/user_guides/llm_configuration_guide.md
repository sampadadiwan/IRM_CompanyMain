# User Guide: Entity-Specific LLM Configuration

This guide explains how to configure Large Language Model (LLM) settings for individual entities within the CapHive platform.

## Overview
Entities can now use their own API keys for Anthropic and OpenRouter, allowing for independent billing and access to specific models.

## Configuration Steps

### 1. Accessing Entity Settings
Navigate to the **Entity Profile** or **Settings** section for the specific entity you wish to configure.

### 2. LLM API Keys
Under the **AI/LLM Settings** (stored in `EntitySetting`), you will find fields for:
- **Anthropic API Key**: Provide your `sk-ant-...` key here to enable Claude-based features.
- **OpenRouter API Key**: Provide your OpenRouter key to access a variety of models via OpenRouter's gateway.

### 3. Default Model Selection
You can specify a **Default LLM Model** for the entity. This model will be the primary choice for AI operations (like portfolio report generation or chat) unless overridden.
- Common values: `claude-3-5-sonnet-latest`, `gpt-4o`, etc. (depending on your provider).

### 4. Verification
Once saved, the system will use these keys for any AI-powered features initiated within the context of this entity.

## Technical Details for Administrators
- **Database Storage**: Keys are stored in the `entity_settings` table (`anthropic_api_key`, `openrouter_api_key`).
- **Model Storage**: The preferred model is stored in `entity_settings.default_llm_model`.
- **Precedence**: If entity-specific keys are missing, the system may fall back to global environment variables (check `.env.production`), but entity keys always take precedence.

## Security Note
API keys are encrypted at rest (if configured in Rails) or stored securely in the database. Ensure that only authorized administrators have access to the Entity Settings page.

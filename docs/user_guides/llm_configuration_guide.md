# User Guide: Entity-Specific LLM Configuration

This guide explains how to configure Large Language Model (LLM) settings for individual entities within the CapHive platform.

> **Where to find it:** Top-bar [**Company menu → Agents**](/support_agents) → **LLM Keys**, which opens the [**AI Provider Keys**](/support_agents/llm_keys) page for provider keys and the **Default LLM Model**; set a single agent's model with **Edit** → **AI Model** on that agent. Needs the **company_admin** role.

## Overview
Each entity can use its own API keys for **OpenAI**, **Anthropic**, **Google Gemini** and **OpenRouter**, allowing for independent billing and access to specific models.

## Configuration Steps

### 1. Accessing Entity Settings
Open the top-bar **Company menu** (the house icon at the top right) and choose [**Agents**](/support_agents), then click **LLM Keys** at the top right. This opens the [**AI Provider Keys**](/support_agents/llm_keys) page. The keys are not on the entity's Company Profile page.

### 2. LLM API Keys
Under **API Keys**, each of the four providers has its own card:
- **OpenAI**: Provide your OpenAI key to enable GPT models.
- **Anthropic**: Provide your `sk-ant-...` key here to enable Claude-based features.
- **Google Gemini**: Provide your Google AI Studio key to enable Gemini models.
- **OpenRouter**: Provide your OpenRouter key to access a variety of models via OpenRouter's gateway.

Paste a key into the provider's field and click **Save Keys**. Leaving a field blank keeps the existing key; tick **Remove** to delete one.

### 3. Default Model Selection
You can specify a **Default LLM Model** for the entity. Only models from providers with a saved key are listed. This model is used by AI operations that do not name a model of their own.
- Support agents are not normally affected: every agent is created with its own **AI Model** already set, and that model takes precedence. To change an agent's model, open the agent and use **Edit** → **AI Model**.

### 4. Verification
Once saved, the page shows **Configured** on each provider card that has a key, and the system uses these keys for AI-powered features run within this entity from the next request.

## Technical Details for Administrators
- **Database Storage**: Keys are stored in the `entity_settings` table (`openai_api_key`, `anthropic_api_key`, `gemini_api_key`, `openrouter_api_key`).
- **Model Storage**: The preferred model is stored in `entity_settings.default_llm_model`; each agent's own model is stored on the agent.
- **Precedence**: Entity keys always take precedence. If an entity has no key for a provider, the system falls back to CapHive's platform credentials for that provider, where CapHive has configured them.

## Security Note
Saved keys are never displayed again on the page, which only shows **Configured** or **Not set** per provider. Only users with the **company_admin** role and CapHive support can open the **AI Provider Keys** page.

## Frequently Asked Questions

### Navigation and getting there

**Where do I enter my organisation's LLM API keys?**
Open the top-bar [**Company menu → Agents**](/support_agents) and click **LLM Keys** at the top right. This opens the [**AI Provider Keys**](/support_agents/llm_keys) page. The keys are not on the Company Profile edit page.

**The Agents item in the Company menu is locked. How do I reach the keys page?**
The menu item is locked when no support agent is enabled for your entity. A company admin can still open the [**AI Provider Keys**](/support_agents/llm_keys) page directly; to unlock the menu, ask CapHive support to enable the agents you need.

**Who can see and change the LLM keys?**
Users with the **company_admin** role in your entity, and CapHive support. Other users do not see the **LLM Keys** button and cannot open the page.

**Where do I set the model for one particular agent?**
Open [**Company menu → Agents**](/support_agents), click the agent's card, then **Edit** on its **General** tab and change **AI Model**. See [Configuring LLM Keys](support_agents_user_guide#3-configuring-llm-keys) in the Support Agents guide.

**Where do I choose the model used to score Customer Support Agent answers?**
Open **Company menu → Company Profile**, click **Edit** and use **Judge Model** in the **CS Agent — Response Quality Judge** section. Leaving it blank uses the default shown next to the field.

### Adding, changing and removing keys

**Which providers can I add keys for?**
Four: **OpenAI**, **Anthropic**, **Google Gemini** and **OpenRouter**. Each provider card on the **AI Provider Keys** page lists the models its key unlocks.

**How do I add a provider key?**
On [**AI Provider Keys**](/support_agents/llm_keys), paste the key into the provider's field and click **Save Keys**. The card then shows a **Configured** badge.

**How do I replace an existing key?**
Type the new key into the provider's field, whose placeholder reads "Enter new key to replace", and click **Save Keys**. Fields you leave blank keep their current key.

**How do I remove a key?**
Tick **Remove** next to the provider's field and click **Save Keys**. The **Remove** box only appears for providers that already have a key.

**How do I set the default model for my organisation?**
On **AI Provider Keys**, pick a model in **Default LLM Model** and click **Save Keys**. Only models from providers with a saved key are listed; choose "No default (use agent setting)" to clear it.

**Can I see a key after I have saved it?**
No. Saved keys are never shown again; the page only shows **Configured** or **Not set** per provider. The eye icon only reveals what you are typing before you save.

### Why configure your own keys

**Why should my organisation use its own LLM keys?**
AI usage is billed to your own provider account, you choose which providers and models process your data, and you can apply your own data-privacy agreements with that provider. Different entities can use different providers.

**What does adding a key let me do?**
It unlocks that provider's models for the **Default LLM Model** list and for each agent's **AI Model**, so agents and other AI features in your entity can run on them. OpenRouter gives access to many third-party models through one key.

**Who typically manages LLM configuration?**
A company admin, usually with IT or compliance, sets it up once when AI features are first enabled and revisits it when a key is rotated or a new model is adopted.

**What happens if I don't add any keys?**
The **Default LLM Model** list stays empty and AI features in your entity fall back to CapHive's platform keys where CapHive has configured them. If there is no key at all for the model an agent uses, that agent's run fails; agents that use no AI still run.

### What happens when I…

**What happens when I click Save Keys?**
New keys and the default model are saved for your entity and you see "LLM keys saved." They are used from the next AI request; runs already in progress are not affected, and no one is notified.

**What happens when I remove a key?**
The key is deleted from your entity straight away. Agents set to that provider's models then use CapHive's platform key if one exists, or fail on their next run, so switch them to another model first.

**What happens when I change the Default LLM Model?**
AI features that do not name their own model use the new default from the next request. Agents keep using their own **AI Model**, which new agents get set to a default when created, so change agents individually.

**What happens if the default model belongs to a provider whose key I later remove?**
The setting is kept, but requests for that model can no longer use your key. Pick a new **Default LLM Model** from a provider that still has a key.

### Troubleshooting and edge cases

**The Default LLM Model dropdown is empty. Why?**
No provider key is saved yet; the page shows "Add at least one API key below to enable model selection." Save a key first, then the models it unlocks appear.

**A model I want is not in the list. Can I add it?**
Not from the screen; the model list per provider is curated by CapHive. Ask CapHive support if you need a model that is not offered, or use OpenRouter for a wider choice.

**An agent failed with an authentication or API key error. What should I check?**
Check that the provider for the agent's **AI Model** shows **Configured** on **AI Provider Keys**, that the key is still valid in the provider's console, and that the account has billing enabled. Replace the key and run the agent again.

**Does changing a key affect other entities?**
No. Keys and the default model are stored per entity, so each entity you manage is configured separately.

**Is the Default LLM Model the same as an agent's AI Model?**
No. An agent's own **AI Model** always takes precedence; the entity default is used only where no model is set for the request.

## Related Guides

- [Support Agents](support_agents_user_guide) — the agents that use these keys, and how to set each agent's AI Model.
- [AI Features](ai_features_user_guide) — the AI features in CapHive that run on your configured providers.
- [Customer Support Agent](customer_support_agent_user_guide) — the support chat and the response-quality judge model.
- [Connect Claude via MCP](mcp_server/user_guide_mcp_connect_claude) — using an external AI client with your own subscription instead of entity keys.

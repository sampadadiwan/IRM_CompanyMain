# AI Assistants Services

This directory contains the core logic for the AI Assistants used throughout the platform. These assistants leverage the `RubyLLM` gem to provide intelligent data retrieval, analysis, and visualization capabilities.

## Architecture

The assistant system follows a clear three-layer separation of concerns:

1.  **Assistants (Orchestrators):** The main entry point (e.g., `FundAssistant`). They define the system persona, manage the conversation lifecycle (via `Chat` models), and register available tools.
2.  **Tools:** Specialized classes (e.g., `FundAssistantTools`) that define the schema and interface for the LLM. They inherit from `RubyLLM::Tool` and act as the "hands" of the assistant.
3.  **Data Managers:** The implementation layer (e.g., `FundAssistantDataManager`). They handle the actual business logic, Pundit-scoped data retrieval, and Ransack filtering.

## Key Assistants

### 1. Fund Assistants
*   [`FundAssistant`](app/packs/ai/assistants/services/fund_assistant.rb): General fund management assistant.
*   [`SpecificFundAssistant`](app/packs/ai/assistants/services/specific_fund_assistant.rb): A specialized version locked to a single `Fund` context.

### 2. Portfolio Assistants
*   [`PortfolioAssistant`](app/packs/ai/assistants/services/portfolio_assistant.rb): Handles cross-portfolio analysis, valuations, and KPIs.
*   [`PortfolioCompanyAssistant`](app/packs/ai/assistants/services/portfolio_company_assistant.rb): Scoped to a single `PortfolioCompany` (Investor).

### 3. Capital Commitment Assistant
*   [`CapitalCommitmentAssistant`](app/packs/ai/assistants/services/capital_commitment_assistant.rb): Specialized for LP-facing queries regarding commitments, remittances, and distributions.

## Common Features

### Data Retrieval & Filtering
Assistants use `Ransack` for flexible querying. The Data Managers translate natural language requirements (e.g., "unpaid", "last 12 months") into Ransack query hashes or predefined scopes using `HasScope`.

### Visualizations
The [`BaseAssistantTools::PlotChart`](app/packs/ai/assistants/services/base_assistant_tools.rb) tool allows assistants to generate interactive `Chart.js` visualizations.
*   **Workflow:** The AI first calls a `list_` tool to gather data, then passes that data to `PlotChart`.
*   **Rendering:** Returns an HTML snippet with a Stimulus controller (`chart-renderer`) for client-side rendering.

### Document Analysis
Assistants can interact with the document management system:
*   `ListDocuments` / `GetDocument`: Metadata and text content retrieval.
*   `AnalyzeDocument`: Uses LLM capabilities to answer questions directly from document attachments (PDFs/Images) using `RubyLLM`.

### Monthly Reports
Many assistants (e.g., `CapitalCommitmentAssistant`, `PortfolioCompanyAssistant`, `SpecificFundAssistant`) include a `run_monthly_report` capability.
*   **Sequential Execution:** It iterates through a predefined set of `MONTHLY_REPORT_QUERIES`.
*   **Ephemeral Chats:** To prevent context window overflow and maintain performance, each query is run in a "fresh" ephemeral chat.
*   **Reliability:** Implements automatic retries with exponential backoff and jitter to handle provider-side rate limits (e.g., `RubyLLM::RateLimitError`).
*   **Token Tracking:** Monitors cumulative input and output tokens across the entire report generation process.

### Hyperlinking
All assistants follow strict hyperlinking rules defined in their system prompts. They use the `view_link` field returned by tools to generate HTML anchors with `target="_blank"`, ensuring the AI response remains integrated with the platform UI.

## Building a New Assistant

To build a new assistant:

1.  **Create a Data Manager:** Implement methods that return clean, serializable hashes/arrays. Use `Pundit.policy_scope` to ensure security.
2.  **Define Tools:** Create a tools file that wraps Data Manager methods in `RubyLLM::Tool` classes. Define clear descriptions and parameters to help the LLM understand when to use them.
3.  **Implement the Assistant:**
    *   Initialize with a `user` and any required `context` (e.g., `fund`).
    *   Define a `system_prompt` with clear instructions and personas.
    *   Implement the `run(prompt)` method to orchestrate the `Chat` and tool execution.

## Special Services

*   [`SlideGeneratorService`](app/packs/ai/assistants/services/slide_generator_service.rb): Transforms a chat transcript into a "Slide Blueprint" (JSON) for generating sophisticated, minimalist presentations.

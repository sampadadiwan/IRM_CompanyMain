# AI Assistants Services

This directory contains the core logic for the AI Assistants used throughout the platform. These assistants leverage the `RubyLLM` gem to provide intelligent data retrieval, analysis, and visualization capabilities.

## Architecture

The assistant system follows a clear three-layer separation of concerns, orchestrated by a common base:

0.  **Base Layer ([`BaseAssistant`](app/packs/ai/assistants/services/base_assistant.rb)):** Provides shared logic for conversation management, tool orchestration, token tracking, and report generation.
1.  **Assistants (Orchestrators):** Domain-specific entry points (e.g., `FundAssistant`) that inherit from `BaseAssistant`. They define the system persona, manage the conversation lifecycle (via `Chat` models), and register available tools.
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

### Efficient Data Handling (Querying & Aggregating)
Assistants are designed to handle large datasets efficiently by delegating filtering and aggregation to the database. This minimizes the volume of data sent to the LLM, preventing context window overflow and reducing costs.

#### 1. Ransack Filtering (`query`)
Most tools accept a `query` object that maps directly to [Ransack](https://github.com/activerecord-hackery/ransack) predicates.
*   **Attributes:** Tools define specific allowed attributes (e.g., `name`, `amount`, `date`).
*   **Predicates:** LLMs use predicates like `_cont` (contains), `_eq` (equals), `_gt` (greater than), `_lteq` (<=) to narrow down results.
*   **Example:** `{ name_cont: 'Venture', amount_gteq: 1000000 }`

#### 2. Predefined Scopes (`scope`)
Common business logic is encapsulated in `HasScope` or ActiveRecord scopes.
*   **Examples:** `verified`, `pending`, `paid`, `master_funds`.
*   **Usage:** Prefer scopes over complex Ransack queries for standard statuses.

#### 3. Sorting & Limiting (`sort`, `limit`)
**CRITICAL:** To maintain efficiency, assistants are instructed to ALWAYS use `sort` and `limit` when fetching lists.
*   **`sort`:** Maps to Ransack `s` (e.g., `created_at desc`, `amount_cents asc`).
*   **`limit`:** Limits the number of records returned to the LLM (e.g., `limit: 10`).

#### 4. Server-Side Aggregation (`aggregate`)
Tools can perform calculations directly in the database, returning only the result rather than the raw records.
*   **`aggregate`:** Supported operations include `count`, `sum`, and `group_by`.
*   **`aggregate_field`:** The field to sum or count (e.g., `amount_cents`).
*   **`group_by_field`:** The field to group results by (e.g., `currency`).
*   **Benefit:** The LLM can answer questions like "What is the total committed amount across all funds?" by receiving a single number instead of thousands of fund records.

### Visualizations
The [`BaseAssistantTools::PlotChart`](app/packs/ai/assistants/services/base_assistant_tools.rb) tool allows assistants to generate interactive `Chart.js` visualizations.
*   **Workflow:** The AI first calls a `list_` tool (often with `limit` or `aggregate`) to gather data, then passes that data to `PlotChart`.
*   **Rendering:** Returns an HTML snippet with a Stimulus controller (`chart-renderer`) for client-side rendering.

### Document Analysis
Assistants can interact with the document management system:
*   `ListDocuments` / `GetDocument`: Metadata and text content retrieval.
*   `AnalyzeDocument`: Uses LLM capabilities to answer questions directly from document attachments (PDFs/Images) using `RubyLLM`.

### Monthly Reports
Many assistants (e.g., `CapitalCommitmentAssistant`, `PortfolioCompanyAssistant`, `SpecificFundAssistant`) include a `run_report` capability, often triggered asynchronously via `AssistantReportJob`.
*   **Sequential Execution:** It iterates through a predefined set of queries (e.g., `MONTHLY_REPORT_QUERIES`).
*   **Ephemeral Chats:** To prevent context window overflow and maintain performance, each query is run in a "fresh" ephemeral chat provided by `BaseAssistant#run_report`.
*   **Reliability:** Implements automatic retries with exponential backoff and jitter to handle provider-side rate limits (e.g., `RubyLLM::RateLimitError`).
*   **Token Tracking:** Monitors cumulative input and output tokens across the entire report generation process.
*   **Clean Responses:** Automatically strips internal LLM "thought" blocks from the final output using `clean_response`.

### Hyperlinking
All assistants follow strict hyperlinking rules defined in their system prompts. They use the `view_link` field returned by tools to generate HTML anchors with `target="_blank"`, ensuring the AI response remains integrated with the platform UI.

## Building a New Assistant

To build a new assistant:

1.  **Create a Data Manager:** Implement methods that return clean, serializable hashes/arrays. Use `Pundit.policy_scope` to ensure security.
2.  **Define Tools:** Create a tools file that wraps Data Manager methods in `RubyLLM::Tool` classes. Define clear descriptions and parameters to help the LLM understand when to use them.
3.  **Implement the Assistant:**
    *   Inherit from [`BaseAssistant`](app/packs/ai/assistants/services/base_assistant.rb).
    *   Initialize with a `user` and any required `context` (e.g., `fund`).
    *   Define a `system_prompt` with clear instructions and personas.
    *   Provide the `tools` list.
    *   (Optional) Define `default_report_queries` to enable the `run_report` capability.

## Special Services

*   [`SlideGeneratorService`](app/packs/ai/assistants/services/slide_generator_service.rb): Transforms a chat transcript into a "Slide Blueprint" (JSON) for generating sophisticated, minimalist presentations.

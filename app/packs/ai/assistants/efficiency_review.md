# AI Tool Efficiency Review & Optimization Recommendations

Based on the **AI Tool Efficiency Report** and an architectural review of the `SpecificFundAssistant`, this document outlines strategies to reduce token usage and improve performance.

## 1. Primary Cost Driver: Chat History Accumulation: TBD from the ruby_llm gem side. There is an open PR, waiting to be merged
The report shows a dramatic escalation in tokens per interaction.
*   **Observation:** Interaction #2 starts at ~3,000 tokens, but by Interaction #18, it exceeds **136,000 tokens**.
*   **Cause:** The `SpecificFundAssistant` uses a persistent `Chat` object. Every new query appends to the message history, including all tool outputs, which is then re-sent to the LLM in every subsequent turn.
*   **Recommendation:** Implement **Context Pruning**. Limit the history sent to the LLM to the last 5-10 messages or use a summarization strategy for older parts of the conversation.

## 2. Redundant Data Retrieval: Done
The assistant often fetches full datasets to perform simple calculations that could be handled server-side.
*   **Example:** Fetching hundreds of capital remittance records just to calculate a total overdue amount.
*   **Recommendation:** Enhance the `aggregate` parameter in `FundAssistantDataManager`.
    *   Add support for `sum`, `average`, and `group_by`.
    *   Example: A single tool call should return `{"Arun Gupta Holding": 7200000, "Investor 11": 240000}` instead of the full JSON for every remittance record.

## 3. Tool Response Bloat
Tool outputs currently include many fields (e.g., `fees`, `verified`, `view_link`, `folio_id`) that are not always needed for every query.
*   **Recommendation:** Implement **Field Selection**.
    *   Add a `fields` parameter to all `list_` tools.
    *   If the assistant only needs the `investor_name` and `call_amount`, the tool should only return those fields, significantly reducing the JSON payload and token count.

## 4. System Prompt Overhead: TBD from the ruby_llm gem side. There is an open PR, waiting to be merged
The `system_prompt` is sent with every message.
*   **Recommendation:**
    *   **Prompt Condensation:** Audit the `system_prompt` for verbosity. Many formatting rules can be simplified.
    *   **Prompt Caching:** Utilize provider-level prompt caching (e.g., Gemini/Anthropic) if available to make the static system prompt and early history cheaper.

## 5. Optimized Chart Flow
Currently, the assistant fetches data and then sends it *back* to the `PlotChart` tool.
*   **Recommendation:** Allow the `PlotChart` tool to optionally accept a query object itself.
    *   Instead of: `fetch_data` -> `received_data` -> `plot_chart(data)`,
    *   Use: `plot_chart(source: 'capital_remittances', query: { ... })`.
    *   This keeps the raw data on the server and only sends the chart HTML/summary back to the LLM.

## 6. Token Usage Summary (from Report)
*   **Total Tokens Used:** 3,156,349
*   **Est. Cost:** $1.7052 (for 45 calls, which is high for the complexity of queries)
*   **Efficiency:** 100% Context used (this indicates the context window is being maxed out, leading to both high cost and potential loss of early instruction adherence).

---

# Optimization Roadmap: HLD & LLD

This section provides a structured plan for implementing the recommendations above.

## A. Context Window Pruning & Pruning Strategy
**Problem:** Persistent chat history leads to exponential token growth, causing high costs and potential model confusion.

### High-Level Design (HLD)
Introduce a "Context Manager" layer in `BaseAssistant` that filters or summarizes the message history before it is sent to the LLM. This ensures only the most relevant context is maintained.

### Low-Level Design (LLD)
*   **Task A.1: History Windowing:** Implement a sliding window in `BaseAssistant#run` that only includes the last $N$ (e.g., 10) messages.
*   **Task A.2: Strategic Message Retention:** Ensure the System Prompt and the *first* User message (often containing the primary goal) are always retained, even if they fall outside the window.
*   **Task A.3: Tool Output Pruning:** When a tool result is very large and has already been summarized by the assistant in a previous turn, replace the original tool message content with a placeholder like `[Large data set previously summarized]`.

## B. Server-Side Aggregations
**Problem:** The assistant fetches hundreds of records just to perform a `sum` or `count`, inflating input tokens.

### High-Level Design (HLD)
Extend the existing `aggregate` functionality in `FundAssistantDataManager` to support complex operations like `sum` and `group_by` using ActiveRecord/SQL instead of LLM processing.

### Low-Level Design (LLD)
*   **Task B.1: Extend `perform_aggregation`:** Update the private method in `FundAssistantDataManager` to handle `sum` and `group_by`.
*   **Task B.2: Tool Parameter Update:** Update `SpecificFundAssistantTools` to accept `aggregate_field` and `group_by_field` parameters.
*   **Task B.3: Prompt Update:** Update the `system_prompt` to explicitly instruct the assistant to use these aggregations for totals and grouping instead of fetching full lists.

## C. Field Selection (Projection)
**Problem:** Tool outputs include redundant fields (IDs, links, metadata) that are often ignored by the assistant but consume tokens.

### High-Level Design (HLD)
Implement a "Projection" layer in the Data Manager that filters the hash/JSON returned by the models based on a requested list of fields.

### Low-Level Design (LLD)
*   **Task C.1: Add `fields` param to Tools:** Update tool definitions to accept an optional `fields` array.
*   **Task C.2: Implement `project_results` helper:** Create a utility in `FundAssistantDataManager` that maps over the result set and keeps only the specified keys.
*   **Task C.3: Dynamic Defaulting:** If no `fields` are specified, default to a "minimal" set (e.g., Name, Date, Amount) instead of all available attributes.

## D. Prompt Optimization & Caching
**Problem:** The static system prompt is large and re-sent with every turn.

### High-Level Design (HLD)
Condense the system prompt to its essential directives and leverage LLM provider features for prompt caching.

### Low-Level Design (LLD)
*   **Task D.1: Prompt Refactoring:** Remove redundant "Hyperlinking Rules" and "Tool Usage Rules" that can be inferred or simplified. Move valid scope lists into tool descriptions themselves rather than the global prompt.
*   **Task D.2: Cache Implementation:** Configure the `RubyLLM` client to signal cacheable blocks (e.g., the system prompt and the first 2k tokens of history).

## E. Direct-to-Chart Data Flow
**Problem:** Moving large datasets from Server -> LLM -> Server (Chart Tool) is extremely inefficient.

### High-Level Design (HLD)
Modify the `PlotChart` tool to allow "Indirect Execution," where it accepts a query definition instead of raw data.

### Low-Level Design (LLD)
*   **Task E.1: Create `plot_from_query` tool:** A new tool action that takes a resource name (e.g., `capital_remittances`) and a Ransack query.
*   **Task E.2: Internal Pipeline:** The tool executes the data manager internally and pipes the result directly into the chart renderer.
*   **Task E.3: Summary Generation:** The tool should return the chart HTML AND a tiny text summary of the data so the LLM knows what was plotted without seeing the raw numbers.

## Implementation Tasks Priority

| ID | Task | Category | Priority |
|:---|:---|:---|:---|
| T1 | Implement sliding window for `@chat.messages` in `BaseAssistant` | Context | Critical |
| T2 | Add `sum` and `group_by` to `perform_aggregation` | Aggregation | High |
| T3 | Add `fields` filter to `list_capital_remittances` & `list_capital_distribution_payments` | Projection | High |
| T4 | Refactor `SpecificFundAssistant#system_prompt` to reduce token count | Prompt | Medium |
| T5 | Update `PlotChart` to accept `data_query` instead of full `data` string | Charting | Done |

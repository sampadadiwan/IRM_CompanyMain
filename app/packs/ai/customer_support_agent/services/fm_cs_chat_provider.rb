# frozen_string_literal: true

# Chat provider for the Customer Support Agent. Scoped to a single FM entity.
# Supplies the system prompt (support-focused), entity context, and the 4 CS tools.
#
# @see BaseChatProvider
# @see GenericChatAgent
class FmCsChatProvider < BaseChatProvider
  # @return [String] system prompt for the Customer Support Agent
  def system_prompt
    <<~PROMPT
      You are a Customer Support Assistant for #{support_agent.entity&.name || 'the fund manager'} on the CapHive platform.
      User: #{analyst&.name || 'Unknown'} (#{analyst&.email})
      Date: #{Date.current.strftime('%d %b %Y')}

      Your role is to help Fund Manager users with platform support questions — how to use features,
      troubleshoot issues, and understand their data.

      ## Data Sources
      You have access to three data sources:
      1. **User Guides** — Platform documentation covering all CapHive features. Search these FIRST for "how to" questions.
      2. **Entity Data** — Live database queries scoped to this fund manager's entity. Use for data-specific questions.
      3. **Past Conversations** — The user's previous support conversations. Use for context on recurring issues.

      ## Response Quality Criteria
      Every response must be:
      - **Complete** — fully answers the question, no missing steps
      - **Grounded** — based on user guides or actual data, not invented
      - **Actionable** — tells the user exactly what to do, step by step

      ## Guidelines
      - Be professional, concise, and helpful
      - For "how to" questions, search user guides FIRST before querying the database
      - For data questions, use the query tool with proper entity scoping
      - Always reference specific feature names, menu paths, or data from your sources
      - Format responses in Markdown — use headers, numbered steps, and bold for emphasis
      - If you find relevant guide content, cite the guide name in your response

      ## Out-of-Scope Behavior
      - If the question is outside your knowledge (not in guides, not answerable from data), say so honestly
      - Offer to connect the user to the Caphive support team using the escalation tool
      - Do NOT attempt a tool call for questions clearly outside platform support (e.g. general knowledge, investment advice)
      - Do NOT make up answers or guess at feature behavior

      ## SQL Placeholders
      Your SQL queries may use these placeholders (substituted with trusted values):
      - {ENTITY_ID} — this fund manager's entity_id. REQUIRED in every query. Use with IN syntax.
      - {FUND_IDS} — all fund_ids in this entity. Optional. Use with IN syntax.

      Example: SELECT name FROM funds WHERE entity_id IN ({ENTITY_ID}) AND id IN ({FUND_IDS})

            ## Available Database Tables
      You can query the following tables (these are the ONLY tables allowed):
      - `funds` — fund name, currency, fund size, entity_id
      - `capital_commitments` — investor commitments to funds
      - `capital_calls` — capital calls made to investors
      - `capital_remittances` — capital call payments received
      - `capital_remittance_payments` — individual remittance payment records
      - `capital_distributions` — distributions made to investors
      - `capital_distribution_payments` — individual distribution payment records
      - `portfolio_investments` — portfolio company investments
      - `aggregate_portfolio_investments` — aggregated portfolio data
      - `investors` — investor records
      - `valuations` — fund/investment valuations
      - `documents` — uploaded documents
      - `folders` — document folders
      - `fund_ratios` — fund performance ratios
      - `investor_kycs` — investor KYC records
      - `whatsapp_logs` — WhatsApp message logs
      - `noticed_notifications` — notification records
      - `investor_accesses` — investor access permissions


      #{strict_scope_prompt}

      #{cs_examples_prompt}
    PROMPT
  end

  # @return [String] entity context block
  def build_context
    return "No user context available." unless analyst

    lines = []
    lines << "## Fund Manager"
    lines << "Entity: #{support_agent.entity&.name} (entity_id: #{support_agent.entity_id})"
    lines << "User: #{analyst.name} (#{analyst.email})"
    lines << ""
    lines << "## Funds in This Entity"
    entity_funds.each do |fund|
      lines << "- #{fund.name} (fund_id: #{fund.id}, currency: #{fund.currency})"
    end
    lines << "(no funds found)" if entity_funds.empty?
    lines.join("\n")
  end

  # @return [Array<RubyLLM::Tool>] the 4 CS tools
  def tools
    [
      FmRunQueryTool.new(
        entity_ids: [support_agent.entity_id],
        accessible_fund_ids: entity_fund_ids
      ),
      SearchUserGuidesTool.new,
      SearchPastMessagesTool.new(
        analyst_id: analyst.id,
        support_agent_id: support_agent.id
      ),
      EscalateToHumanTool.new(
        session: chat_session,
        user: analyst,
        entity: support_agent.entity
      )
    ]
  end

  # @return [Integer] cap tool iterations at 6 to prevent runaway loops
  def max_tool_iterations
    6
  end

  # @return [AgentChatSession, nil]
  attr_writer :chat_session

  private

  # @return [Array<Fund>]
  def entity_funds
    @entity_funds ||= Fund.where(entity_id: support_agent.entity_id, deleted_at: nil).to_a
  end

  # @return [Array<Integer>]
  def entity_fund_ids
    @entity_fund_ids ||= entity_funds.map(&:id)
  end

  def chat_session
    @chat_session ||= AgentChatSession.where(
      support_agent: support_agent,
      analyst: analyst
    ).order(updated_at: :desc).first
  end

  # @return [String] few-shot examples loaded from cs_examples.md, if it exists
  def cs_examples_prompt
    examples_path = Rails.root.join("docs/user_guides/cs_examples.md")
    return "" unless File.exist?(examples_path)

    content = File.read(examples_path)
    <<~PROMPT
      ## Example Q&A
      Below are examples of good support responses. Follow this style:

      #{content}
    PROMPT
  end
end

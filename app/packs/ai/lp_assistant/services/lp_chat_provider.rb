# frozen_string_literal: true

# Chat provider for the LP (Limited Partner) assistant. Scoped to a single
# Fund Manager entity (the SupportAgent's entity). Provides the system
# prompt, an LP-scoped context listing the investor's accessible funds in
# that FM, and the four progressive-disclosure tools (list_skills,
# load_skill, run_query, document_url).
# @see BaseChatProvider
# @see GenericChatAgent
class LpChatProvider < BaseChatProvider
  # @return [String] system prompt for the LP assistant
  def system_prompt
    <<~PROMPT
            You are an AI assistant for a Limited Partner (investor) of #{support_agent.entity&.name || 'the fund house'}.
            User: #{analyst&.name || 'Unknown'}
            Date: #{Date.current.strftime('%d %b %Y')}

            Your role is to help the investor understand their fund data — performance metrics
            (NAV, IRR, TVPI, DPI), commitments, capital calls, distributions, and portfolio companies.

            Guidelines:
            - Be professional and concise
            - Reference specific fund names and numbers from the data
            - Format currency values clearly (use the fund's currency)
            - If you don't have data to answer, say so honestly

      IMPORTANT: your SQL may reference these literal placeholders and they will be substituted:
        - {ENTITY_ID}    — the Fund Manager entity_id this chat is scoped to. Use with IN
                          for consistency (e.g. `entity_id IN ({ENTITY_ID})`).
        - {FUND_IDS}     — comma-separated fund ids this investor can access within this FM
                          (always required, use IN).
        - {INVESTOR_IDS} — comma-separated investors.id rows for THIS LP org in this FM's
                          books. Include this filter ONLY when querying per-LP tables
                          (capital_commitments, capital_remittances,
                          capital_distribution_payments, or fund_ratios with
                          owner_type = 'Investor' / 'CapitalCommitment'). Do NOT use it on
                          fund-level tables (portfolio_investments, funds,
                          fund_ratios owner_type='Fund').
        - {VISIBLE_API_IDS} / {VISIBLE_PI_IDS} — the portfolio holdings this investor may see
                          (aggregate_portfolio_investments.id / portfolio_investments.id). Always
                          required when querying those tables (e.g. `api.id IN ({VISIBLE_API_IDS})`);
                          never answer about other holdings.
      Example: WHERE cc.entity_id IN ({ENTITY_ID})
                AND cc.fund_id IN ({FUND_IDS})
                AND cc.investor_id IN ({INVESTOR_IDS})


      NARROWING:
      - {ENTITY_ID}, {FUND_IDS}, and {INVESTOR_IDS} are the security ceiling —
        always include them, never drop them.
      - If the user asks about a SUBSET of funds (e.g. "only Growth Fund"), add
        a SEPARATE filter using literal fund_ids read from the "Accessible Funds"
        context block:
            AND fr.fund_id IN ({FUND_IDS})    -- trusted scope (never drop)
            AND fr.fund_id IN (12)            -- your narrow from context
      - If the user asks about ALL their funds, no narrow needed — {FUND_IDS}
        covers everything in scope.



            WORKFLOW (progressive disclosure):
            1. Call list_skills to see available data domains.
            2. Call load_skill(skill_name) for the domain most relevant to the question.
            3. Write a SQL query following the schema and examples, using the placeholder
               contract above. The tool REJECTS any query missing {ENTITY_ID} or {FUND_IDS}.
            4. Call run_query(sql) to execute. Format the result naturally for the investor.
            5. If the skill tells you a row contains a document_id, call document_url(document_id: N)
               to get a clickable download URL, then embed that URL as a Markdown link in your reply.
               Never fabricate URLs, never link to /documents/<id> paths.
            6. If a tool returns an error, read it carefully and retry with corrected input.

            ## Output Formatting (DEFAULT BEHAVIOR)

            - ALWAYS format query results as a Markdown table when the result has 2+ rows OR 2+ columns. Do this by default — do not wait for the user to ask.
            - Use standard Markdown table syntax with a header row and separator:
              | Fund Name | TVPI |
              |-----------|------|
              | Fund 1    | 15.65x |
            - Single scalar answers ("Your DPI is 1.45x") don't need a table.
            - Use `display_value` for user-facing numbers when available; otherwise round `value` to 2 decimals.
            - For documents (SOA etc.), render the filename as a Markdown link `[filename](url)` using the URL from `document_url`.
            - Do NOT wrap tables in ``` code fences — emit raw Markdown so the chat UI renders them.
            - When a value is missing for a fund, still include the row and write "—" or "N/A" in the cell (don't drop the row into a prose sentence at the end, like "I do not have TVPI data for New Test Fund").



            #{strict_scope_prompt}

            #{table_rendering_prompt}

            #{chart_rendering_prompt}

            #{whatsapp_formatting_prompt if channel == 'whatsapp'}
    PROMPT
  end

  # Builds the context block injected into the system prompt: LP identity,
  # the single FM this chat is scoped to, the accessible funds within that
  # FM, and the LP org's investor_ids for use in the {INVESTOR_IDS} placeholder.
  # @return [String] markdown context block
  def build_context
    return "No investor user context available." unless analyst

    funds = accessible_funds
    return "No accessible funds for this investor in #{support_agent.entity&.name}." if funds.empty?

    lines = []
    lines << "## Investor"
    lines << "Name: #{analyst.name}"
    lines << "Fund Manager: #{support_agent.entity&.name} (entity_id: #{support_agent.entity_id})"
    lines << ""
    lines << "## Accessible Funds"
    funds.each do |fund|
      lines << "- #{fund.name} (fund_id: #{fund.id}, currency: #{fund.currency})"
    end
    lines << ""
    lines << "## LP Org Investor IDs (use in {INVESTOR_IDS} placeholder)"
    lines << if accessible_investor_ids.any?
               "investor_ids: #{accessible_investor_ids.join(', ')}"
             else
               "(no investor rows found for this LP org in #{support_agent.entity&.name}'s books)"
             end
    lines.join("\n")
  end

  # Progressive-disclosure toolset exposed to the LLM: discover → load → query → link.
  # @return [Array<RubyLLM::Tool>]
  def tools
    entity_ids   = accessible_entity_ids
    fund_ids     = accessible_funds.map(&:id)
    investor_ids = accessible_investor_ids

    [
      ListSkillsTool.new,
      LoadSkillTool.new,
      # Portfolio rows are limited to the holdings this LP may see (LpPortfolioVisibility — H19, E69–E71)
      RunQueryTool.new(
        entity_ids: entity_ids,
        accessible_fund_ids: fund_ids,
        accessible_investor_ids: investor_ids,
        visible_api_ids: portfolio_visibility.assistant_api_ids(support_agent.entity_id),
        visible_pi_ids: portfolio_visibility.assistant_pi_ids(support_agent.entity_id)
      ),
      DocumentUrlTool.new(
        entity_ids: entity_ids,
        accessible_fund_ids: fund_ids,
        accessible_investor_ids: investor_ids
      )
    ]
  end

  private

  # LP can only see funds within this SupportAgent's entity (the GP whose chat
  # they are currently using). Fund.for_investor enforces AccessRight; the
  # entity_id filter scopes to this single FM.
  # @return [Array<Fund>]
  def accessible_funds
    @accessible_funds ||= Fund.for_investor(analyst)
                              .where(entity_id: support_agent.entity_id)
                              .joins(:entity)
                              .where(entities: { deleted_at: nil })
                              .distinct
                              .to_a
  end

  # Single FM entity_id this chat is scoped to. Kept as an array so
  # RunQueryTool's IN ({ENTITY_ID}) substitution stays uniform.
  # @return [Array<Integer>] one-element list containing support_agent.entity_id
  # The LP's visible portfolio holdings (the same rule as every LP portfolio screen)
  def portfolio_visibility
    @portfolio_visibility ||= LpPortfolioVisibility.for_user(analyst)
  end

  def accessible_entity_ids
    @accessible_entity_ids ||= [support_agent.entity_id]
  end

  # Investors.id rows representing this LP org in THIS GP's books only.
  # @return [Array<Integer>]
  def accessible_investor_ids
    return [] unless analyst

    @accessible_investor_ids ||= Investor.where(
      entity_id: support_agent.entity_id,
      investor_entity_id: analyst.entity_id,
      deleted_at: nil
    ).pluck(:id)
  end

  def whatsapp_formatting_prompt
    <<~PROMPT

      ## WhatsApp Formatting
      This conversation is on WhatsApp. Adjust your formatting:
      - Use plain text, NOT HTML tables or tags
      - Use *bold* for emphasis (WhatsApp bold syntax)
      - Use line breaks and vertical bars for tabular data
      - Keep responses concise — under 2000 characters when possible
      - For documents, provide the download URL as a plain link
      - Do NOT output chart or canvas HTML — describe data in plain text instead
    PROMPT
  end
end

# frozen_string_literal: true

# Chat provider for the LP (Limited Partner) assistant.
# Provides the system prompt and an LP-scoped context listing the
# investor's accessible funds. Tools (list_skills, load_skill, run_query)
# will be added in subsequent steps to enable progressive disclosure.
#
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
        - {ENTITY_ID}    — comma-separated Fund Manager entity ids this LP has funds with
                          (ALWAYS use with IN). One LP login can span multiple FMs — e.g. an
                          LP invested in both Kedara and Fireside sees both entity_ids here.
        - {FUND_IDS}     — comma-separated fund ids this investor can access (always required, use IN)
        - {INVESTOR_IDS} — comma-separated investors.id rows for THIS LP org across ALL FMs
                          they have invested with. Include this filter ONLY when querying
                          per-LP tables (capital_commitments, capital_remittances,
                          capital_distribution_payments, or fund_ratios with
                          owner_type = 'Investor' / 'CapitalCommitment'). Do NOT use it on
                          fund-level tables (portfolio_investments, funds,
                          fund_ratios owner_type='Fund').
      Example: WHERE cc.entity_id IN ({ENTITY_ID})
                AND cc.fund_id IN ({FUND_IDS})
                AND cc.investor_id IN ({INVESTOR_IDS})

      SCOPE vs NARROW — two-layer filtering:
      - {ENTITY_ID}, {FUND_IDS}, and {INVESTOR_IDS} are the SECURITY ceiling —
        every id the LP is allowed to see. Always include them. Never drop them.
      - When the user asks for a SUBSET (e.g. "just Kedara funds", "only Growth
        Fund", "my Fireside IRRs"), add a SEPARATE narrower filter using literal
        ids you read from the "Accessible Funds" context block. Combine both:
            AND fr.fund_id IN ({FUND_IDS})    -- trusted scope (never drop)
            AND fr.fund_id IN (11, 12)        -- your narrow from context
      - For fund-level narrowing pick fund_ids from the Accessible Funds list.
        For FM-level narrowing (e.g. "Kedara funds"), use the fund_ids under
        that FM's group in the context block — NOT a literal entity_id.
      - If the user asks about ALL their funds, skip the narrow — {FUND_IDS}
        alone covers everything they can see.


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
    PROMPT
  end

  # @return [String] lightweight context: LP identity + accessible funds
  #   grouped by Fund Manager (entity). The grouping lets the LLM resolve
  #   questions like "IRR for Kedara funds" by picking fund_ids under the
  #   Kedara group without ever needing to write a literal entity_id.
  def build_context
    return "No investor user context available." unless analyst

    funds = accessible_funds
    return "No accessible funds for this investor." if funds.empty?

    lines = []
    lines << "## Investor"
    lines << "Name: #{analyst.name}"
    lines << "Accessible FM entity_ids: #{accessible_entity_ids.join(', ')}"
    lines << ""
    lines << "## Accessible Funds (grouped by Fund Manager)"
    funds.group_by(&:entity).each do |entity, fm_funds|
      fm_name = entity&.name || "(unknown FM)"
      fm_id   = entity&.id   || 'n/a'
      lines << ""
      lines << "### #{fm_name} (entity_id: #{fm_id})"
      fm_funds.each do |fund|
        lines << "- #{fund.name} (fund_id: #{fund.id}, currency: #{fund.currency})"
      end
    end
    lines << ""
    lines << "## LP Org Investor IDs (use in {INVESTOR_IDS} placeholder)"
    lines << if accessible_investor_ids.any?
               "investor_ids: #{accessible_investor_ids.join(', ')}"
             else
               "(no investor rows found for this LP org across any FM's books)"
             end
    lines.join("\n")
  end

  # @return [Array<RubyLLM::Tool>] progressive disclosure tools
  # Progressive-disclosure toolset exposed to the LLM: discover → load → query → link.
  # @return [Array<RubyLLM::Tool>]
  def tools
    [
      ListSkillsTool.new,
      LoadSkillTool.new,
      RunQueryTool.new(
        entity_ids: accessible_entity_ids,
        accessible_fund_ids: accessible_funds.map(&:id),
        accessible_investor_ids: accessible_investor_ids
      ),
      DocumentUrlTool.new(
        entity_ids: accessible_entity_ids,
        accessible_fund_ids: accessible_funds.map(&:id),
        accessible_investor_ids: accessible_investor_ids
      )
    ]
  end

  private

  # Cross-FM: Fund.for_investor(analyst) already traverses access_rights +
  # investor_accesses and returns funds spanning every FM the LP has approved
  # access with. The previous `.where(entity_id: support_agent.entity_id)`
  # filter silently dropped cross-FM funds and has been removed. The
  # SupportAgent row remains the per-entity routing/config anchor, not a
  # scope gate.
  def accessible_funds
    @accessible_funds ||= Fund.for_investor(analyst)
                              .joins(:entity)
                              .where(entities: { deleted_at: nil })
                              .includes(:entity)
                              .distinct
                              .to_a
  end

  # Distinct FM entity_ids the LP has funds with — used to substitute {ENTITY_ID}
  # as a comma-joined list for cross-FM-safe `entity_id IN ({ENTITY_ID})` filters.
  def accessible_entity_ids
    @accessible_entity_ids ||= accessible_funds.map(&:entity_id).uniq
  end

  # Every investors.id in every FM's book that represents THIS LP org.
  # Widened from a single support_agent.entity_id to the full set of FM
  # entities the LP has funds with, so {INVESTOR_IDS} correctly spans FMs.
  def accessible_investor_ids
    @accessible_investor_ids ||= Investor.where(
      entity_id: accessible_entity_ids,
      investor_entity_id: analyst&.entity_id,
      deleted_at: nil
    ).pluck(:id)
  end
end

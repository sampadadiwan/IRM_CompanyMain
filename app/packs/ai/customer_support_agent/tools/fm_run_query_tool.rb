# frozen_string_literal: true

# Subclass of RunQueryTool for FM (Fund Manager) users in the Customer Support Agent.
# Key differences from the LP RunQueryTool:
#   - Wider table allowlist (adds investor_kycs, whatsapp_logs, noticed_notifications, investor_accesses)
#   - Only {ENTITY_ID} is mandatory — no {FUND_IDS} requirement (FM users are entity-scoped, not fund-scoped)
#   - Entity scoping: single entity_id, not cross-FM
#
# @see RunQueryTool
# @see FmCsChatProvider
class FmRunQueryTool < RunQueryTool
  description "Execute a read-only MySQL SELECT query. The SQL MUST include " \
              "the literal placeholder {ENTITY_ID} where scoping applies — " \
              "e.g. `WHERE entity_id IN ({ENTITY_ID})`. The placeholder expands " \
              "to the FM's entity id, so always use `IN (...)` syntax. " \
              "Optionally use {FUND_IDS} to scope by fund. " \
              "Queries missing {ENTITY_ID} are rejected. Returns up to 100 rows " \
              "formatted as a Markdown table."

  parameter :sql,
            type: :string,
            description: 'MySQL SELECT with {ENTITY_ID} placeholder (required, used with IN). {FUND_IDS} optional.',
            required: true

  ALLOWED_TABLES = (RunQueryTool::ALLOWED_TABLES + %w[
    investor_kycs
    whatsapp_logs
    noticed_notifications
    investor_accesses
  ]).freeze

  # @param entity_ids [Array<Integer>] single-element list with the FM's entity_id
  # @param accessible_fund_ids [Array<Integer>] all fund_ids in this entity
  def initialize(entity_ids:, accessible_fund_ids:)
    super(entity_ids: entity_ids, accessible_fund_ids: accessible_fund_ids, accessible_investor_ids: [])
  end

  # Override: skip the fund-check guard from RunQueryTool.
  # FM entities may have no funds yet but still need entity-scoped queries.
  # Only the entity_id check matters for CS agent queries.
  def execute(sql:)
    return 'No accessible fund manager entities for this investor.' if @entity_ids.empty?

    error = validate(sql)
    if error
      Rails.logger.warn(
        "[cs_agent][FmRunQueryTool] REJECTED — reason=#{error}\n  llm_sql=#{sql}"
      )
      return "Query rejected: #{error}"
    end

    safe_sql = substitute_and_limit(sql)
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = ActiveRecord::Base.connection.exec_query(safe_sql, 'CS Agent Query')
    Rails.logger.info("[cs_agent] FmRunQueryTool took #{((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round}ms sql=#{sql.first(200)}")
    format_result(result)
  rescue ActiveRecord::StatementInvalid => e
    Rails.logger.error(
      "[cs_agent][FmRunQueryTool] SQL FAILED — #{e.class}: #{e.message.lines.first&.strip}\n  " \
      "llm_sql=#{sql}\n  executed_sql=#{safe_sql}"
    )
    "SQL execution failed: #{e.message.lines.first&.strip}"
  end

  private

  # @param sql [String]
  # @return [String, nil] rejection reason, or nil if valid
  def validate(sql)
    stripped = sql.to_s
                  .gsub(%r{/\*.*?\*/}m, '')
                  .gsub(/--[^\n]*/, '')
                  .strip

    return 'only SELECT queries are allowed.' unless /\Aselect\s/i.match?(stripped)

    upper = stripped.upcase
    kw = FORBIDDEN_KEYWORDS.find { |w| upper.match?(/\b#{w}\b/) }
    return "forbidden keyword: #{kw}" if kw

    return 'comma-separated FROM lists are not allowed; use explicit JOIN syntax.' if stripped.match?(/\bFROM\s+`?\w+`?\s*,/i)

    tables = stripped.scan(/(?:\bFROM|\bJOIN)\s+`?(\w+)`?/i).flatten.map(&:downcase).uniq
    invalid = tables - ALLOWED_TABLES
    return "tables not allowed: #{invalid.join(', ')}" if invalid.any?

    return 'missing {ENTITY_ID} placeholder — scope required.' unless sql.include?('{ENTITY_ID}')

    nil
  end
end

# frozen_string_literal: true

# Tool that executes a read-only MySQL SELECT query on behalf of the LP Assistant.
# Enforces the LP's scope through placeholder substitution, table whitelisting,
# and SQL keyword validation. The LLM's SQL must contain `{ENTITY_ID}` and
# `{FUND_IDS}` placeholders; it may additionally use `{INVESTOR_IDS}` for per-LP
# tables. The tool substitutes all three with trusted comma-joined integer lists
# supplied by LpChatProvider. Any query missing {ENTITY_ID} or {FUND_IDS} is
# rejected.
#
# {ENTITY_ID} is the single FM entity_id; IN syntax kept for uniformity.
#
# Security layers:
#   1. SELECT-only (rejects WITH, INSERT, UPDATE, DELETE, DDL, etc.)
#   2. Forbidden keyword blocklist
#   3. Table whitelist (ALLOWED_TABLES)
#   4. Required placeholders {ENTITY_ID} and {FUND_IDS};
#      optional {INVESTOR_IDS} for per-LP tables (capital_commitments,
#      capital_remittances, capital_distribution_payments, and fund_ratios
#      when owner_type IN ('Investor','CapitalCommitment')).
#   5. Placeholder substitution with integer-cast, trusted values
#   6. Hard LIMIT 100
#
# @see LpChatProvider
class RunQueryTool < RubyLLM::Tool
  description "Execute a read-only MySQL SELECT query. The SQL MUST include " \
              "the literal placeholders {ENTITY_ID} and {FUND_IDS} where scoping " \
              "applies — e.g. `WHERE entity_id IN ({ENTITY_ID}) AND fund_id IN ({FUND_IDS})`. " \
              "Both placeholders expand to comma-joined id lists, so always use " \
              "`IN (...)` syntax. The tool substitutes these with the LP's trusted " \
              "values. Queries missing either placeholder are rejected. Returns " \
              "up to 100 rows formatted as a Markdown table."

  param :sql,
        type: :string,
        desc: 'MySQL SELECT with {ENTITY_ID} and {FUND_IDS} placeholders (both used with IN).',
        required: true

  ALLOWED_TABLES = %w[
    fund_ratios
    funds
    capital_commitments
    capital_calls
    capital_remittances
    capital_remittance_payments
    capital_distributions
    capital_distribution_payments
    portfolio_investments
    aggregate_portfolio_investments
    investors
    valuations
    documents
    folders
  ].freeze

  FORBIDDEN_KEYWORDS = %w[INSERT UPDATE DELETE DROP ALTER TRUNCATE GRANT REVOKE CREATE].freeze
  MAX_ROWS = 100

  # @param entity_ids [Array<Integer>] single-element list with the scoped FM entity_id.
  # @param accessible_fund_ids [Array<Integer>] — substitutes {FUND_IDS}
  # @param accessible_investor_ids [Array<Integer>] — substitutes {INVESTOR_IDS}; defaults to []
  def initialize(entity_ids:, accessible_fund_ids:, accessible_investor_ids: [])
    super()
    @entity_ids = Array(entity_ids).map(&:to_i).uniq
    @accessible_fund_ids = accessible_fund_ids.map(&:to_i).uniq
    @accessible_investor_ids = accessible_investor_ids.map(&:to_i).uniq
  end

  # @param sql [String] SELECT query containing {ENTITY_ID} and {FUND_IDS} placeholders
  # @return [String] formatted markdown table, or an error/rejection string
  def execute(sql:)
    return 'No accessible funds for this investor.' if @accessible_fund_ids.empty?
    return 'No accessible fund manager entities for this investor.' if @entity_ids.empty?

    if sql.include?('{INVESTOR_IDS}') && @accessible_investor_ids.empty?
      return 'No investor records found for this LP in the requested scope. ' \
             'This may indicate missing data setup — please contact your fund manager.'
    end

    error = validate(sql)
    if error
      Rails.logger.warn(
        "[lp_assistant][RunQueryTool] REJECTED — reason=#{error}\n  " \
        "llm_sql=#{sql}"
      )
      return "Query rejected: #{error}"
    end

    safe_sql = substitute_and_limit(sql)
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = ActiveRecord::Base.connection.exec_query(safe_sql, 'LP Assistant Query')
    Rails.logger.info("[lp_assistant] RunQueryTool took #{((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round}ms sql=#{sql.first(200)}")
    format_result(result)
  rescue ActiveRecord::StatementInvalid => e
    Rails.logger.error(
      "[lp_assistant][RunQueryTool] SQL FAILED — #{e.class}: #{e.message.lines.first&.strip}\n  " \
      "llm_sql=#{sql}\n  " \
      "executed_sql=#{safe_sql}"
    )
    "SQL execution failed: #{e.message.lines.first&.strip}"
  end

  private

  # @param sql [String]
  # @return [String, nil] rejection reason, or nil if the query passes all guards
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
    return 'missing {FUND_IDS} placeholder — scope required.'  unless sql.include?('{FUND_IDS}')

    nil
  end

  # @param sql [String]
  # @return [String] SQL with placeholders substituted and LIMIT 100 applied if absent
  def substitute_and_limit(sql)
    investor_ids_sql = @accessible_investor_ids.join(',')
    investor_ids_sql = 'NULL' if investor_ids_sql.empty? # only hit when {INVESTOR_IDS} not in sql

    substituted = sql.gsub('{ENTITY_ID}',    @entity_ids.join(','))
                     .gsub('{FUND_IDS}',     @accessible_fund_ids.join(','))
                     .gsub('{INVESTOR_IDS}', investor_ids_sql)
                     .sub(/;\s*\z/, '')

    substituted.match?(/\blimit\s+\d/i) ? substituted : "#{substituted} LIMIT #{MAX_ROWS}"
  end

  # @param result [ActiveRecord::Result]
  # @return [String] markdown table rendering
  def format_result(result)
    return '(no rows)' if result.rows.empty?

    headers = result.columns
    rows = result.rows.first(MAX_ROWS)
    lines = ["| #{headers.join(' | ')} |", "| #{headers.map { '---' }.join(' | ')} |"]
    rows.each { |r| lines << "| #{r.map { |v| v.nil? ? '' : v.to_s }.join(' | ')} |" }
    lines << ''
    lines << "(#{rows.size} row#{'s' unless rows.size == 1})"
    lines.join("\n")
  end
end

# frozen_string_literal: true

# Subclass of RunQueryTool for FM (Fund Manager) users in the Customer Support Agent.
# Key differences from the LP RunQueryTool:
#   - Wider table allowlist (adds investor_kycs, whatsapp_logs, noticed_notifications, investor_accesses)
#   - Only {ENTITY_ID} is mandatory — no {FUND_IDS} requirement (FM users are entity-scoped, not fund-scoped)
#   - Entity scoping: single entity_id, not cross-FM
#
# Security (follow-up F1 to H5 — the same layers as the LP tool):
#   1–3. RunQueryTool#statement_error: literals and comments stripped first; SELECT only; WITH, INTO,
#        LOAD_FILE, SLEEP, BENCHMARK, GET_LOCK, `@` and a second statement refused; no schema / database
#        names; no real table outside ALLOWED_TABLES wherever it appears (comma list, parentheses, subquery).
#   4.   {ENTITY_ID} required, checked on the stripped SQL (a placeholder inside a comment does not count).
#   5.   FmQueryScope CTEs shadow every allowed table with this entity's rows only (the real control), so a
#        dropped or neutralised entity filter still sees only the FM's own data.
#   6.   LIMIT 100; MySQL MAX_EXECUTION_TIME hint and read-only transaction; while_preventing_writes.
#
# Worked examples F1-1…F1-5, F1-H — features/security/security_review_2026_10_followups.feature
#
# @see RunQueryTool
# @see FmQueryScope
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

    # Shared statement checks, then the FM placeholder rule
    error = validate(sql)
    if error
      Rails.logger.warn(
        "[cs_agent][FmRunQueryTool] REJECTED — reason=#{error}\n  llm_sql=#{sql}"
      )
      return "Query rejected: #{error}"
    end

    # The model's SELECT, placeholders filled, behind the entity's scope CTEs, run read-only
    safe_sql = scoped_sql(sql)
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = run_read_only(safe_sql, 'CS Agent Query')
    Rails.logger.info("[cs_agent] FmRunQueryTool took #{((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round}ms sql=#{sql.first(200)}")
    format_result(result)
  rescue ActiveRecord::StatementInvalid, ActiveRecord::ReadOnlyError => e
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
    # Literals, keywords, schemas and tables outside the FM's CTEs (F1-2…F1-4)
    error, stripped, = statement_error(sql, fm_scope.tables)
    return error if error

    # Placeholders count only outside literals and comments (F1-5)
    return 'missing {ENTITY_ID} placeholder — scope required.' unless stripped.include?('{ENTITY_ID}')

    nil
  end

  # This FM entity's rows behind every allowed table (F1-1)
  def fm_scope
    @fm_scope ||= FmQueryScope.new(entity_id: @entity_ids.first, tables: ALLOWED_TABLES)
  end

  # The executed statement: the FM scope CTEs, then the model's SELECT with placeholders filled, LIMIT
  # applied and (MySQL) the execution-time hint
  def scoped_sql(sql)
    "#{fm_scope.with_clause}\n#{with_execution_time_hint(substitute_and_limit(sql))}"
  end
end

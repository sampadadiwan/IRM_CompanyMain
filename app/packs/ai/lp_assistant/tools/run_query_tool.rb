# frozen_string_literal: true

# Tool that executes a read-only SELECT query on behalf of the LP Assistant.
#
# The LLM writes the SQL, so the scope is put on the DATA, not on the SQL text (finding H5):
# LpQueryScope prefixes the statement with one CTE per allowed table, built from ActiveRecord
# relations for this LP (`WITH funds AS (…), capital_commitments AS (…), … <model's SELECT>`).
# A CTE name shadows the real table everywhere in the statement, so a comma join, a parenthesised
# join or a dropped investor filter can only ever see this LP's rows.
#
# Security layers (LP path):
#   1. Literals and comments are stripped before any check (so a keyword inside a string is not
#      mistaken for SQL, and a placeholder inside a comment does not count); optimizer hints,
#      executable comments and backslashes are rejected outright.
#   2. SELECT-only; forbidden keyword blocklist, plus WITH, INTO, LOAD_FILE, SLEEP, BENCHMARK,
#      GET_LOCK, `@` variables and a second statement.
#   3. Any identifier naming a real table outside ALLOWED_TABLES is rejected (wherever it appears —
#      FROM, JOIN, comma list, parentheses, subquery), and so is any database / schema name
#      (information_schema, mysql, performance_schema, sys, the app's own database), so the model
#      cannot write a qualified name that reaches past the CTEs.
#   4. Required placeholders {ENTITY_ID} and {FUND_IDS}, and {VISIBLE_API_IDS} / {VISIBLE_PI_IDS} for
#      the portfolio tables — checked on the stripped SQL, substituted with trusted integer lists.
#   5. LpQueryScope CTEs over every allowed table (the real control).
#   6. Hard LIMIT 100; on MySQL a 5 s MAX_EXECUTION_TIME hint and a read-only transaction; always
#      inside ActiveRecord's while_preventing_writes.
#
# FmRunQueryTool shares layers 1–3 (statement_error), the execution guards of layer 6 and the
# substitution / formatting helpers; its scope CTEs come from FmQueryScope (entity-wide, follow-up F1).
#
# Worked examples H5-1…H5-5, H5-H, H5-X — features/security/lp_assistant_run_query.feature
#
# @see LpChatProvider
# @see LpQueryScope
class RunQueryTool < RubyLLM::Tool
  description "Execute a read-only MySQL SELECT query. The SQL MUST include " \
              "the literal placeholders {ENTITY_ID} and {FUND_IDS} where scoping " \
              "applies — e.g. `WHERE entity_id IN ({ENTITY_ID}) AND fund_id IN ({FUND_IDS})`. " \
              "Both placeholders expand to comma-joined id lists, so always use " \
              "`IN (...)` syntax. The tool substitutes these with the LP's trusted " \
              "values. Queries missing either placeholder are rejected. Returns " \
              "up to 100 rows formatted as a Markdown table."

  parameter :sql,
            type: :string,
            description: 'MySQL SELECT with {ENTITY_ID} and {FUND_IDS} placeholders (both used with IN).',
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
  # The statement's own LIMIT: its last clause (LIMIT n, LIMIT m, n or LIMIT n OFFSET m)
  TRAILING_LIMIT = /\blimit\s+\d+(?:\s*,\s*\d+|\s+offset\s+\d+)?\s*\z/i

  # H5 / F1 — both assistants (statement_error). A model-written WITH
  # could not reach past the scope CTEs either, but is refused so the statement stays one SELECT.
  FORBIDDEN_LP_KEYWORDS = %w[WITH INTO LOAD_FILE SLEEP BENCHMARK GET_LOCK].freeze
  # Schemas that would reach outside the scope CTEs (the app's own database names are added at run time)
  FORBIDDEN_SCHEMAS = %w[information_schema mysql performance_schema sys main temp sqlite_master sqlite_schema
                         sqlite_temp_master].freeze
  # MySQL MAX_EXECUTION_TIME hint, in milliseconds
  MAX_EXECUTION_MS = 5000

  # @param entity_ids [Array<Integer>] single-element list with the scoped FM entity_id.
  # @param accessible_fund_ids [Array<Integer>] — substitutes {FUND_IDS}
  # @param accessible_investor_ids [Array<Integer>] — substitutes {INVESTOR_IDS}; defaults to []
  # @param visible_api_ids / visible_pi_ids [Array<Integer>] — the LP's visible holdings and their purchases
  #   (LpPortfolioVisibility); substitute {VISIBLE_API_IDS} / {VISIBLE_PI_IDS}
  # @param user [User, nil] — the LP, for the documents scope (LpQueryScope); without it no documents are visible
  def initialize(entity_ids:, accessible_fund_ids:, accessible_investor_ids: [], visible_api_ids: [], visible_pi_ids: [], user: nil)
    super()
    @visible_api_ids = visible_api_ids.map(&:to_i).uniq
    @visible_pi_ids = visible_pi_ids.map(&:to_i).uniq
    @entity_ids = Array(entity_ids).map(&:to_i).uniq
    @accessible_fund_ids = accessible_fund_ids.map(&:to_i).uniq
    @accessible_investor_ids = accessible_investor_ids.map(&:to_i).uniq
    @user = user
  end

  # Names of every table / view in the database (fixed between deploys, so memoised per process)
  def self.real_table_names
    @real_table_names ||= ActiveRecord::Base.connection.data_sources.to_set(&:downcase)
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

    # The model's SELECT, placeholders filled, behind the LP's scope CTEs
    safe_sql = scoped_sql(sql)
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = run_read_only(safe_sql)
    Rails.logger.info("[lp_assistant] RunQueryTool took #{((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round}ms sql=#{sql.first(200)}")
    format_result(result)
  rescue ActiveRecord::StatementInvalid, ActiveRecord::ReadOnlyError => e
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
    # The checks both assistants share (literals, keywords, schemas, tables outside the CTEs)
    error, stripped, identifiers = statement_error(sql, LpQueryScope.tables)
    return error if error

    # Placeholders count only outside literals and comments
    return 'missing {ENTITY_ID} placeholder — scope required.' unless stripped.include?('{ENTITY_ID}')
    return 'missing {FUND_IDS} placeholder — scope required.'  unless stripped.include?('{FUND_IDS}')

    # X18 / H5-X — portfolio tables are limited to the LP's visible holdings, never the whole fund
    tables = identifiers.map(&:first) & LpQueryScope.tables
    return 'missing {VISIBLE_API_IDS} placeholder — scope required.' if tables.include?('aggregate_portfolio_investments') && stripped.exclude?('{VISIBLE_API_IDS}')
    return 'missing {VISIBLE_PI_IDS} placeholder — scope required.' if tables.include?('portfolio_investments') && stripped.exclude?('{VISIBLE_PI_IDS}')

    nil
  end

  # The statement checks shared by the LP tool and FmRunQueryTool (H5 fix 2; F1 for the FM tool).
  # @param sql [String] the model's SQL
  # @param scope_tables [Array<String>] the tables the caller's scope CTEs shadow — the only real tables allowed
  # @return [Array(String|nil, String, Array)] rejection reason (nil = passes), the stripped SQL, its identifiers
  def statement_error(sql, scope_tables)
    # Backslashes are refused: MySQL and SQLite read them differently inside literals, and the
    # literal stripping below must see the same literals the database does
    return ['backslashes are not allowed.', '', []] if sql.to_s.include?('\\')

    # Every later check reads the SQL with literals and comments taken out
    stripped, error = strip_literals_and_comments(sql)
    return [error, stripped, []] if error
    return ['only SELECT queries are allowed.', stripped, []] unless /\Aselect\s/i.match?(stripped)

    # Statement-level bans: the existing blocklist, then WITH / INTO / file and timing functions (H5-5, F1-4)
    upper = stripped.upcase
    kw = (FORBIDDEN_KEYWORDS + FORBIDDEN_LP_KEYWORDS).find { |w| upper.match?(/\b#{w}\b/) }
    return ["forbidden keyword: #{kw}", stripped, []] if kw
    return ['user and system variables (@) are not allowed.', stripped, []] if stripped.include?('@')
    return ['only one statement is allowed.', stripped, []] if stripped.sub(/;\s*\z/, '').include?(';')

    # Identifier checks (H5-2, H5-3, F1-2, F1-3): no schema / database names, no real table outside the allowlist
    identifiers = sql_identifiers(stripped)
    schema = identifiers.map(&:first).find { |name| forbidden_schema_names.include?(name) }
    return ["schema not allowed: #{schema}", stripped, identifiers] if schema

    # A name after a dot is a column of an alias (cap_call.notes), not a table; anywhere else it is a table
    # reference, and only the tables the caller's scope shadows are allowed
    invalid = identifiers.reject(&:last).map(&:first).select { |name| self.class.real_table_names.include?(name) } - scope_tables
    if invalid.any?
      # A column that shares a table's name (notes) reads as that table unless written alias.column
      return ["tables not allowed: #{invalid.uniq.join(', ')} — if you meant a column of that name, write it as alias.column.",
              stripped, identifiers]
    end

    [nil, stripped, identifiers]
  end

  # Replaces literals with '' and comments with a space. Double-quoted and backticked text is kept
  # as bare words, so the identifier checks see it (it is an identifier in SQLite / with backticks).
  # @param sql [String]
  # @return [Array(String, String|nil)] the stripped SQL and a rejection reason, if any
  def strip_literals_and_comments(sql)
    error = nil
    stripped = sql.to_s.gsub(sql_token_regex) do |token|
      case token
      when %r{\A/\*[!+]}
        # MySQL runs /*! … */ and reads /*+ … */ as optimizer hints: never accept them from the model
        error ||= 'optimizer hints and executable comments are not allowed.'
        ' '
      when %r{\A(?:/\*|--|\#)} then ' '
      when /\A'/ then "''"
      else " #{token[1...-1]} "
      end
    end
    [stripped.strip, error]
  end

  # Literals, quoted identifiers and comments as each database reads them: MySQL treats "-- " (dash
  # dash space) and "#" as comments, SQLite any "--"
  def sql_token_regex
    if LpQueryScope.mysql?
      %r{'(?:[^']|'')*'|"(?:[^"]|"")*"|`(?:[^`]|``)*`|/\*.*?\*/|--(?=\s|\z)[^\n]*|\#[^\n]*}m
    else
      %r{'(?:[^']|'')*'|"(?:[^"]|"")*"|`(?:[^`]|``)*`|/\*.*?\*/|--[^\n]*}m
    end
  end

  # Every word in the stripped SQL, downcased, with whether it follows a dot (alias.column)
  # @return [Array<Array(String, Boolean)>]
  def sql_identifiers(stripped)
    stripped.scan(/(\.\s*)?\b([a-z_][a-z0-9_$]*)/i).map { |dot, name| [name.downcase, dot.present?] }
  end

  # System schemas plus every database this connection can name (so `db`.`users` is refused)
  def forbidden_schema_names
    @forbidden_schema_names ||= begin
      conn = ActiveRecord::Base.connection
      databases = if LpQueryScope.mysql?
                    conn.select_values('SHOW DATABASES')
                  else
                    conn.select_rows('PRAGMA database_list').map(&:second)
                  end
      (FORBIDDEN_SCHEMAS + databases.compact.map(&:downcase)).to_set
    end
  end

  # The executed statement: scope CTEs, then the model's SELECT with placeholders filled, LIMIT
  # applied and (MySQL) the execution-time hint after its leading SELECT
  def scoped_sql(sql)
    scope = LpQueryScope.new(user: @user, entity_id: @entity_ids.first, fund_ids: @accessible_fund_ids,
                             investor_ids: @accessible_investor_ids, visible_api_ids: @visible_api_ids,
                             visible_pi_ids: @visible_pi_ids)
    "#{scope.with_clause}\n#{with_execution_time_hint(substitute_and_limit(sql))}"
  end

  # MySQL only: MAX_EXECUTION_TIME hint after the statement's leading SELECT (shared with FmRunQueryTool)
  def with_execution_time_hint(query)
    return query unless LpQueryScope.mysql?

    query.sub(%r{\A(\s*(?:(?:--|\#)[^\n]*\n\s*|/\*.*?\*/\s*)*)select\b}im) do
      "#{Regexp.last_match(1)}SELECT /*+ MAX_EXECUTION_TIME(#{MAX_EXECUTION_MS}) */"
    end
  end

  # Runs the statement with writes refused: always ActiveRecord's while_preventing_writes; on MySQL
  # also a read-only transaction. SET TRANSACTION READ ONLY applies to the next transaction, which
  # the block below opens — skipped when a transaction is already open, since MySQL refuses to
  # change an open transaction's characteristics.
  # @param name [String] the log label (shared with FmRunQueryTool)
  def run_read_only(sql, name = 'LP Assistant Query')
    conn = ActiveRecord::Base.connection
    ActiveRecord::Base.while_preventing_writes do
      next conn.exec_query(sql, name) unless LpQueryScope.mysql? && !conn.transaction_open?

      conn.execute('SET TRANSACTION READ ONLY')
      conn.transaction { conn.exec_query(sql, name) }
    end
  end

  # @param sql [String]
  # @return [String] SQL with comments removed, placeholders substituted and LIMIT 100 applied if absent
  def substitute_and_limit(sql)
    investor_ids_sql = @accessible_investor_ids.join(',')
    investor_ids_sql = 'NULL' if investor_ids_sql.empty? # only hit when {INVESTOR_IDS} not in sql

    # Comments out first (validate read the statement without them too): a trailing "-- …" swallowed
    # the " LIMIT 100" appended after it, so the query ran unlimited (F5-6). Then the trailing ";".
    query = without_comments(sql).strip.sub(/;\s*\z/, '')

    substituted = query.gsub('{ENTITY_ID}',    @entity_ids.join(','))
                       .gsub('{FUND_IDS}',     @accessible_fund_ids.join(','))
                       .gsub('{INVESTOR_IDS}', investor_ids_sql)
                       .gsub('{VISIBLE_API_IDS}', @visible_api_ids.join(',').presence || 'NULL')
                       .gsub('{VISIBLE_PI_IDS}', @visible_pi_ids.join(',').presence || 'NULL')

    # The model's own LIMIT counts only as the statement's last clause, read outside literals: a LIMIT
    # inside a subquery or a string used to stand in for it and leave the outer SELECT unlimited
    return substituted if strip_literals_and_comments(substituted).first.match?(TRAILING_LIMIT)

    # On a line of its own, so nothing left on the model's last line can reach it
    "#{substituted}\nLIMIT #{MAX_ROWS}"
  end

  # The SQL with every comment replaced by a space; literals and quoted identifiers are kept as written.
  # An unclosed /* is dropped to the end too: SQLite reads it as a comment running to the end of the
  # statement (it would swallow the LIMIT line), MySQL refuses it.
  def without_comments(sql)
    unclosed_block_comment = %r{/\*(?!.*?\*/).*\z}m
    sql.to_s.gsub(Regexp.union(sql_token_regex, unclosed_block_comment)) do |token|
      # Comments become a space; literals, quoted names and everything else stay
      token.match?(%r{\A(?:/\*|--|\#)}) ? ' ' : token
    end
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

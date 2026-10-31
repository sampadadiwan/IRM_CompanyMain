# frozen_string_literal: true

# The data a fund manager user may read through the Customer Support Agent's run_query tool
# (security review 2026-10, follow-up F1 — the FM counterpart of LpQueryScope / H5).
#
# FmRunQueryTool executes SQL the LLM writes. Its placeholders say what the query is meant to see:
# {ENTITY_ID} is "this fund manager's entity" and {FUND_IDS} "all funds of this entity". Checking the
# SQL text for that filter can always be missed (a comma join, a parenthesised join, `OR 1=1`), so the
# scope is put on the data instead: every allowed table is shadowed by a CTE of the same name holding
# only this entity's rows,
#
#   WITH funds AS (SELECT funds.* FROM `db`.`funds` funds WHERE funds.entity_id = 42), … <the model's SELECT>
#
# A CTE name shadows the real table everywhere in the statement, subqueries included, in both MySQL 8
# and SQLite. The CTE body reads the *schema-qualified* real table, which always means the base table,
# never a CTE; FmRunQueryTool rejects any database name in the model's SQL, so the model cannot write a
# qualified name itself.
#
# Every column stays: the FM reads its own entity's records, as on its screens. Rows are entity-wide —
# the same reach {ENTITY_ID} always had — not narrowed to one user's access rights.
#
# Worked examples F1-1…F1-5, F1-H — features/security/security_review_2026_10_followups.feature
class FmQueryScope
  # @param entity_id [Integer] the fund manager entity the CS agent is configured for
  # @param tables [Array<String>] the tool's allowlist (FmRunQueryTool::ALLOWED_TABLES)
  def initialize(entity_id:, tables:)
    @entity_id = Integer(entity_id)
    @tables = tables
  end

  # The allowlisted tables that exist in this database — a name in the allowlist with no table behind
  # it (whatsapp_logs) gets no CTE, and a query naming it fails in the database as before
  # @return [Array<String>]
  def tables
    @tables.select { |table| RunQueryTool.real_table_names.include?(table) }
  end

  # "WITH funds AS (…), …" — always every table, so shadowing never depends on what the model's SQL names
  # @return [String]
  def with_clause
    ctes = tables.map { |table| "#{connection.quote_table_name(table)} AS (#{body_for(table)})" }
    "WITH #{ctes.join(', ')}"
  end

  private

  def connection
    ActiveRecord::Base.connection
  end

  # SELECT <table>.* FROM <qualified real table> <table> WHERE <table>.entity_id = <entity> — the alias
  # keeps a `table.column` reference inside the body pointing at the real rows
  def body_for(table)
    name = connection.quote_table_name(table)
    # @entity_id is an Integer (initialize), so it is safe to inline
    "SELECT #{name}.* FROM #{qualified(table)} #{name} WHERE #{name}.#{connection.quote_column_name('entity_id')} = #{@entity_id}"
  end

  # `IRM_production`.`funds` on MySQL, "main"."funds" on SQLite
  def qualified(table)
    schema = LpQueryScope.mysql? ? connection.current_database : "main"
    connection.quote_table_name("#{schema}.#{table}")
  end
end

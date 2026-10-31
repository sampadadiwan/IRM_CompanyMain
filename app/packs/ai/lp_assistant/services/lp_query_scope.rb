# frozen_string_literal: true

# The data an LP may read through the LP assistant's run_query tool (finding H5).
#
# RunQueryTool executes SQL the LLM writes. Checking that text for the right filters can always be
# missed (a comma join, a parenthesised join, a dropped investor filter), so the scope is put on the
# data instead: every allowed table is shadowed by a common table expression of the same name,
#
#   WITH funds AS (…), capital_commitments AS (…), … <the model's SELECT>
#
# and a CTE name shadows the real table everywhere in the statement, subqueries included, in both
# MySQL 8 and SQLite. Whatever the model writes, `capital_commitments` means "this LP's commitments".
#
# Each CTE is built from an ActiveRecord relation over the *schema-qualified* real table
# (`db`.`funds` / "main"."funds"): a qualified name always means the base table, never a CTE, so the
# CTE bodies cannot read each other by accident, and RunQueryTool rejects any database name in the
# model's SQL so the model cannot write a qualified name itself.
#
# Per-table rules (docs/security/security_review_2026_10.md, H5 fix 1):
#   funds                          — the LP's funds
#   capital_commitments            — own investor rows, in the LP's funds
#   capital_remittances            — own investor rows, in the LP's funds
#   capital_remittance_payments    — payments against those remittances
#   capital_distribution_payments  — own investor rows, in the LP's funds
#   capital_calls / _distributions — the LP's funds
#   portfolio_investments          — visible purchases only (LpPortfolioVisibility)
#   aggregate_portfolio_investments— visible holdings only
#   fund_ratios                    — fund-level, visible holdings / companies, or own investor / commitments
#   investors                      — own investor rows and visible portfolio companies, never pan / json_fields
#   valuations                     — visible portfolio companies
#   documents                      — Document.for_investor minus templates
#   folders                        — the folders of those documents
# Column lists are what the skills document (app/packs/ai/lp_assistant/skills/*.md).
#
# Worked examples H5-1, H5-4, H5-H, H5-X — features/security/lp_assistant_run_query.feature
class LpQueryScope
  # Columns each CTE exposes — what the skills document, plus funds.features (the portfolio skill's LP
  # visibility gate reads it) and aggregate_portfolio_investments.portfolio_company_name (the holdings
  # name the assistant lists). Anything else (pan, json_fields, file_data, bank details …) is simply not
  # there: a query naming it fails with "unknown column", which the model reads and corrects.
  COLUMNS = {
    "funds" => %w[id entity_id name currency data_room_folder_id features deleted_at],
    "capital_commitments" => %w[id entity_id fund_id investor_id commitment_date committed_amount_cents call_amount_cents
                                collected_amount_cents distribution_amount_cents adjustment_amount_cents arrear_amount_cents
                                orig_committed_amount_cents folio_currency folio_id folio_committed_amount_cents
                                folio_call_amount_cents folio_collected_amount_cents percentage total_fund_units_quantity
                                investor_name fund_close onboarding_completed compliant notes deleted_at],
    "capital_calls" => %w[id entity_id fund_id call_date due_date name call_basis notes approved deleted_at],
    "capital_remittances" => %w[id entity_id fund_id capital_call_id capital_commitment_id investor_id call_amount_cents
                                collected_amount_cents arrear_amount_cents capital_fee_cents other_fee_cents
                                committed_amount_cents folio_call_amount_cents folio_collected_amount_cents folio_id
                                remittance_date payment_date status percentage deleted_at],
    "capital_remittance_payments" => %w[id entity_id fund_id capital_remittance_id investor_id amount_cents payment_date
                                        reference_no folio_amount_cents deleted_at],
    "capital_distributions" => %w[id entity_id fund_id distribution_date title notes approved completed deleted_at],
    "capital_distribution_payments" => %w[id entity_id fund_id capital_distribution_id capital_commitment_id investor_id
                                          payment_date gross_payable_cents net_payable_cents income_cents
                                          income_with_fees_cents cost_of_investment_cents cost_of_investment_with_fees_cents
                                          reinvestment_cents reinvestment_with_fees_cents folio_amount_cents folio_id
                                          units_quantity completed notification_sent deleted_at],
    "portfolio_investments" => %w[id entity_id fund_id portfolio_company_id portfolio_company_name investment_date amount_cents
                                  net_amount_cents net_quantity fmv_cents gain_cents cost_of_remaining_cents cost_of_sold_cents
                                  category investment_domicile proforma aggregate_portfolio_investment_id deleted_at],
    "aggregate_portfolio_investments" => %w[id entity_id fund_id portfolio_company_id portfolio_company_name bought_amount_cents
                                            bought_quantity sold_amount_cents sold_quantity cost_of_remaining_cents fmv_cents
                                            gain_cents avg_cost_cents quantity portfolio_income_cents investment_type
                                            show_portfolio snapshot snapshot_date deleted_at],
    "fund_ratios" => %w[id entity_id fund_id name value display_value end_date owner_type owner_id scenario latest
                        capital_commitment_id label notes valuation_id portfolio_scenario_id deleted_at created_at updated_at],
    "investors" => %w[id entity_id investor_name category sector city deleted_at],
    "valuations" => %w[id entity_id owner_type owner_id valuation_date valuation_cents per_share_value_cents
                       net_valuation_cents synthetic deleted_at],
    # file_data is left out: it is the Shrine storage blob, which the skill says never to select
    "documents" => %w[id entity_id folder_id owner_type owner_id name owner_tag approved template created_at updated_at
                      deleted_at],
    "folders" => %w[id entity_id name full_path owner_type owner_id deleted_at]
  }.freeze

  # The model behind each table, for its relation (unscoped: soft-deleted rows stay, as the skills filter them)
  MODELS = {
    "funds" => "Fund", "capital_commitments" => "CapitalCommitment", "capital_calls" => "CapitalCall",
    "capital_remittances" => "CapitalRemittance", "capital_remittance_payments" => "CapitalRemittancePayment",
    "capital_distributions" => "CapitalDistribution", "capital_distribution_payments" => "CapitalDistributionPayment",
    "portfolio_investments" => "PortfolioInvestment", "aggregate_portfolio_investments" => "AggregatePortfolioInvestment",
    "fund_ratios" => "FundRatio", "investors" => "Investor", "valuations" => "Valuation", "documents" => "Document",
    "folders" => "Folder"
  }.freeze

  # Is the app on MySQL (production) rather than SQLite (tests)? Decides the qualifier and the execution guards.
  def self.mysql?
    ActiveRecord::Base.connection.adapter_name.match?(/mysql|trilogy/i)
  end

  # The tables this scope shadows — the LP tool's allowlist
  def self.tables
    COLUMNS.keys
  end

  # @param user [User, nil] the LP — needed only for the documents rule (nil = no documents)
  # @param entity_id [Integer] the fund manager this chat is scoped to
  # @param fund_ids / investor_ids / visible_api_ids / visible_pi_ids [Array<Integer>] the trusted ids LpChatProvider
  #   already computes for the placeholders
  def initialize(user:, entity_id:, fund_ids:, investor_ids:, visible_api_ids:, visible_pi_ids:)
    @user = user
    @entity_id = entity_id.to_i
    @fund_ids = fund_ids.map(&:to_i).uniq
    @investor_ids = investor_ids.map(&:to_i).uniq
    @visible_api_ids = visible_api_ids.map(&:to_i).uniq
    @visible_pi_ids = visible_pi_ids.map(&:to_i).uniq
  end

  # "WITH funds AS (…), …" — always every table, so shadowing never depends on what the model's SQL names
  # @return [String]
  def with_clause
    ctes = COLUMNS.keys.map { |table| "#{connection.quote_table_name(table)} AS (#{relation_for(table).to_sql})" }
    "WITH #{ctes.join(', ')}"
  end

  private

  def connection
    ActiveRecord::Base.connection
  end

  # The scoped rows of one table, selecting only its documented columns
  def relation_for(table)
    base = base_relation(table)
    case table
    when "funds"
      base.where(id: @fund_ids, entity_id: @entity_id)
    when "capital_commitments", "capital_remittances", "capital_distribution_payments"
      # H5-1 — per-LP tables: own investor rows only, whatever the model's WHERE says
      base.where(entity_id: @entity_id, fund_id: @fund_ids, investor_id: @investor_ids)
    when "capital_remittance_payments"
      # Payments are reached through their remittance (investor_id is not filled on older payments)
      base.where(entity_id: @entity_id, fund_id: @fund_ids, capital_remittance_id: own_remittances)
    when "capital_calls", "capital_distributions"
      base.where(entity_id: @entity_id, fund_id: @fund_ids)
    when "portfolio_investments"
      # H5-X — visible purchases only
      base.where(entity_id: @entity_id, id: @visible_pi_ids)
    when "aggregate_portfolio_investments"
      base.where(entity_id: @entity_id, id: @visible_api_ids)
    when "fund_ratios"
      fund_ratio_rows(base)
    when "investors"
      # H5-4 — own rows and visible companies; pan / json_fields are not in the column list
      base.where(entity_id: @entity_id, id: @investor_ids + visible_company_ids)
    when "valuations"
      base.where(entity_id: @entity_id, owner_type: "Investor", owner_id: visible_company_ids)
    when "documents"
      base.where(id: document_ids)
    when "folders"
      base.where(id: folder_ids)
    end
  end

  # SELECT <documented columns> FROM <qualified real table> <table> — the alias keeps ActiveRecord's
  # "table"."column" references pointing at the real rows inside the CTE body
  def base_relation(table)
    model = MODELS.fetch(table).constantize
    columns = COLUMNS.fetch(table) & model.column_names
    model.unscoped.from("#{qualified(table)} #{connection.quote_table_name(table)}").select(*columns.map(&:to_sym))
  end

  # `IRM_production`.`funds` on MySQL, "main"."funds" on SQLite
  def qualified(table)
    schema = self.class.mysql? ? connection.current_database : "main"
    connection.quote_table_name("#{schema}.#{table}")
  end

  # Fund-level ratios (not tied to another LP's commitment), ratios on visible holdings and companies,
  # and ratios on the LP's own investor rows and commitments
  def fund_ratio_rows(base)
    fund_level = base.where(owner_type: "Fund", owner_id: @fund_ids, capital_commitment_id: [nil, *own_commitment_ids])
    rows = fund_level
           .or(base.where(owner_type: "CapitalCommitment", owner_id: own_commitment_ids))
           .or(base.where(owner_type: "Investor", owner_id: @investor_ids + visible_company_ids))
           .or(base.where(owner_type: "PortfolioCompany", owner_id: visible_company_ids))
           .or(base.where(owner_type: "AggregatePortfolioInvestment", owner_id: @visible_api_ids))
           .or(base.where(owner_type: "PortfolioInvestment", owner_id: @visible_pi_ids))
    rows.where(entity_id: @entity_id, fund_id: @fund_ids)
  end

  # Subquery over the real remittances table: this LP's remittances in their funds
  def own_remittances
    CapitalRemittance.unscoped.from("#{qualified('capital_remittances')} #{connection.quote_table_name('capital_remittances')}")
                     .where(entity_id: @entity_id, fund_id: @fund_ids, investor_id: @investor_ids).select(:id)
  end

  # This LP's commitments in their funds — a handful of ids
  def own_commitment_ids
    @own_commitment_ids ||= CapitalCommitment.unscoped.where(entity_id: @entity_id, fund_id: @fund_ids, investor_id: @investor_ids)
                                             .pluck(:id)
  end

  # Portfolio companies of the visible holdings (investors rows of category portfolio company)
  def visible_company_ids
    @visible_company_ids ||= AggregatePortfolioInvestment.unscoped.where(id: @visible_api_ids)
                                                         .unscope(:order).distinct.pluck(:portfolio_company_id)
  end

  # The documents the LP's documents screen lists (Document.for_investor), never templates
  def document_ids
    return [] if @user.nil?

    @document_ids ||= Document.for_investor(@user, @entity_id).not_templates.where(entity_id: @entity_id)
                              .unscope(:order).distinct.pluck(:id)
  end

  # The folders those documents sit in
  def folder_ids
    @folder_ids ||= Document.unscoped.where(id: document_ids).unscope(:order).distinct.pluck(:folder_id)
  end
end

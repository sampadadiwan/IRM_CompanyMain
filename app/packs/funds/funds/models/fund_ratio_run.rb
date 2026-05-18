# Records the exact parameters used in one invocation of FundRatiosScenarioJob.
# One record is created per unique (entity, end_date, fingerprint) combination.
# All FundRatio rows produced by that run reference this record via the polymorphic
# computation_context association on FundRatio.
#
# Design rationale, JSON indexing, and fingerprint details: docs/features/fund_ratio_run.md
class FundRatioRun < ApplicationRecord
  # MySQL rejects literal defaults on JSON columns, so we declare them here instead.
  # These ensure new records always have arrays rather than nil, even before save.
  attribute :fund_ids,              :json, default: -> { [] }
  attribute :portfolio_company_ids, :json, default: -> { [] }
  attribute :sectors,               :json, default: -> { [] }

  belongs_to :entity
  # anchor_fund is the fund the user launched the job from. Used only for document
  # folder resolution and policy scoping — it does not limit which data feeds the calc.
  belongs_to :anchor_fund, class_name: "Fund", optional: true
  belongs_to :user
  # Polymorphic parent side — nullify so FundRatio rows survive if the run is deleted.
  has_many :fund_ratios, as: :computation_context, dependent: :nullify

  # Expose #fund so FundRatio can duck-type across FundRatioRun and PortfolioScenario
  # without branching: both respond to computation_context.fund.
  alias_method :fund, :anchor_fund

  # name is the canonical fingerprint — set automatically before validation.
  validates :name, presence: true, uniqueness: { scope: %i[entity_id end_date] }
  before_validation :set_name, on: :create

  # Returns the canonical fingerprint string for the given filter inputs.
  # All segment values are sorted so order never affects the result.
  # Called on write (before_validation) and on read (for_filter scope) to guarantee
  # the same string is produced for the same logical inputs at both ends.
  def self.fingerprint(fund_ids: [], portfolio_company_ids: [], tags: nil, sectors: [])
    parts = []
    parts << "F:#{Array(fund_ids).map(&:to_i).sort.join(',')}"                          if fund_ids.present?
    parts << "PC:#{Array(portfolio_company_ids).map(&:to_i).sort.join(',')}"            if portfolio_company_ids.present?
    parts << "Tag:#{tags.to_s.split(',').map(&:strip).reject(&:blank?).sort.join(',')}" if tags.present?
    parts << "S:#{Array(sectors).map(&:strip).reject(&:blank?).sort.join(',')}"         if sectors.present?
    # SHA-256 digest keeps the name within VARCHAR(255) regardless of how many IDs are passed.
    # The raw inputs are preserved in fund_ids / portfolio_company_ids / sectors / portfolio_companies_tags columns.
    Digest::SHA256.hexdigest(parts.join(' '))
  end

  # Finds the unique run matching the given dashboard filter params.
  # Computes the fingerprint and does a single indexed WHERE name = ? lookup.
  scope :for_filter, ->(entity_id:, end_date:, fund_ids: [], portfolio_company_ids: [], tags: nil, sectors: []) {
    where(
      entity_id:,
      end_date:,
      name: fingerprint(fund_ids:, portfolio_company_ids:, tags:, sectors:)
    )
  }

  # MEMBER OF uses the multi-valued index on the JSON array column (MySQL 8.0.17+).
  # Each array element gets its own index entry, so these queries hit the index rather
  # than doing a full-table scan. See docs/features/fund_ratio_run.md — "JSON Array Indexing".
  # SQLite (used in tests) does not support MEMBER OF — use json_each() instead.
  scope :for_source_fund, ->(id) {
    if connection.adapter_name.downcase.include?("sqlite")
      where("EXISTS (SELECT 1 FROM json_each(fund_ratio_runs.fund_ids) WHERE value = ?)", id)
    else
      where("? MEMBER OF (fund_ids)", id)
    end
  }

  scope :for_source_portfolio_company, ->(id) {
    if connection.adapter_name.downcase.include?("sqlite")
      where("EXISTS (SELECT 1 FROM json_each(fund_ratio_runs.portfolio_company_ids) WHERE value = ?)", id)
    else
      where("? MEMBER OF (portfolio_company_ids)", id)
    end
  }

  scope :for_source_sector, ->(sector) {
    if connection.adapter_name.downcase.include?("sqlite")
      where("EXISTS (SELECT 1 FROM json_each(fund_ratio_runs.sectors) WHERE value = ?)", sector)
    else
      where("? MEMBER OF (sectors)", sector)
    end
  }

  # portfolio_companies_tags is stored as a raw comma-separated string (not a JSON array),
  # so MEMBER OF is not available. We wrap the column with sentinel commas so that
  # searching for ",tag," avoids false partial matches (e.g. "growth" matching "regrowth").
  # sanitize_sql_like escapes any % or _ in the tag before it enters the LIKE pattern.
  # CONCAT is MySQL-only; SQLite uses the || concatenation operator.
  scope :for_source_tag, ->(tag) {
    safe_tag = "%,#{sanitize_sql_like(tag.to_s.strip)},%"
    if connection.adapter_name.downcase.include?("sqlite")
      where("(',' || portfolio_companies_tags || ',') LIKE ?", safe_tag)
    else
      where("CONCAT(',', portfolio_companies_tags, ',') LIKE ?", safe_tag)
    end
  }

  # Convenience — resolves the stored IDs back to ActiveRecord relations.
  # Note: these are not associations, so they won't be eager-loadable via includes.
  def source_funds
    Fund.where(id: fund_ids)
  end

  def source_portfolio_companies
    Investor.where(id: portfolio_company_ids)
  end

  private

  def set_name
    self.name ||= self.class.fingerprint(
      fund_ids:              fund_ids,
      portfolio_company_ids: portfolio_company_ids,
      tags:                  portfolio_companies_tags,
      sectors:               sectors
    )
  end
end

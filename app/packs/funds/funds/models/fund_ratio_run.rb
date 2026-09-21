# Records the exact parameters used in one invocation of FundRatiosScenarioJob.
# One record is created per unique (entity, end_date, fingerprint) combination.
# All FundRatio rows produced by that run reference this record via the polymorphic
# computation_context association on FundRatio.
#
# Design rationale, JSON indexing, and fingerprint details: docs/modules/funds/fund_ratios/fund_ratio_run.md
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
  belongs_to :fund_ratio_run_template, optional: true
  # Polymorphic parent side — nullify so FundRatio rows survive if the run is deleted.
  has_many :fund_ratios, as: :computation_context, dependent: :nullify

  # Expose #fund so FundRatio can duck-type across FundRatioRun and PortfolioScenario
  # without branching: both respond to computation_context.fund.
  alias fund anchor_fund

  # name is the canonical fingerprint — set automatically before validation.
  validates :name, presence: true, uniqueness: { scope: %i[entity_id end_date] }
  before_validation :set_name, on: :create

  # Returns the canonical fingerprint string for the given filter inputs.
  # All segment values are sorted so order never affects the result.
  # Called on write (before_validation) and on read (for_filter scope) to guarantee
  # the same string is produced for the same logical inputs at both ends.
  def self.fingerprint(fund_ids: [], portfolio_company_ids: [], tags: nil, sectors: [], type: nil)
    parts = []
    parts << "F:#{Array(fund_ids).map(&:to_i).sort.join(',')}"                          if fund_ids.present?
    parts << "PC:#{Array(portfolio_company_ids).map(&:to_i).sort.join(',')}"            if portfolio_company_ids.present?
    parts << "Tag:#{tags.to_s.split(',').map(&:strip).compact_blank.sort.join(',')}" if tags.present?
    parts << "S:#{Array(sectors).map(&:strip).compact_blank.sort.join(',')}"         if sectors.present?
    parts << "T:#{type}"                                                                if type.present?
    # SHA-256 digest keeps the name within VARCHAR(255) regardless of how many IDs are passed.
    # The raw inputs are preserved in fund_ids / portfolio_company_ids / sectors / portfolio_companies_tags columns.
    Digest::SHA256.hexdigest(parts.join(' '))
  end

  # Finds the unique run matching the given dashboard filter params.
  # Computes the fingerprint and does a single indexed WHERE name = ? lookup.
  scope :for_filter, lambda { |entity_id:, end_date:, fund_ids: [], portfolio_company_ids: [], tags: nil, sectors: []|
    where(
      entity_id:,
      end_date:,
      name: fingerprint(fund_ids:, portfolio_company_ids:, tags:, sectors:)
    )
  }

  # MEMBER OF uses the multi-valued index on the JSON array column (MySQL 8.0.17+).
  # Each array element gets its own index entry, so these queries hit the index rather
  # than doing a full-table scan. See docs/modules/funds/fund_ratios/fund_ratio_run.md — "JSON Array Indexing".
  # SQLite (used in tests) does not support MEMBER OF — use json_each() instead.
  scope :for_source_fund, lambda { |id|
    if connection.adapter_name.downcase.include?("sqlite")
      where("EXISTS (SELECT 1 FROM json_each(fund_ratio_runs.fund_ids) WHERE CAST(value AS INTEGER) = ?)", id.to_i)
    else
      where("JSON_CONTAINS(fund_ids, CAST(? AS JSON))", id.to_i)
    end
  }

  scope :for_source_portfolio_company, lambda { |id|
    if connection.adapter_name.downcase.include?("sqlite")
      where("EXISTS (SELECT 1 FROM json_each(fund_ratio_runs.portfolio_company_ids) WHERE CAST(value AS INTEGER) = ?)", id.to_i)
    else
      where("JSON_CONTAINS(portfolio_company_ids, CAST(? AS JSON))", id.to_i)
    end
  }

  scope :for_source_sector, lambda { |sector|
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
  scope :for_source_tag, lambda { |tag|
    safe_tag = "%,#{sanitize_sql_like(tag.to_s.strip)},%"
    if connection.adapter_name.downcase.include?("sqlite")
      where("(',' || portfolio_companies_tags || ',') LIKE ?", safe_tag)
    else
      where("CONCAT(',', portfolio_companies_tags, ',') LIKE ?", safe_tag)
    end
  }

  # Convenience — resolves the stored IDs back to ActiveRecord relations.
  # Note: these are not associations, so they won't be eager-loadable via includes.
  # Human-readable summary of the scope/filter inputs that produced this run.
  # Uses only stored columns so it is safe to call in a loop without N+1 queries.
  # Example: "Cross-portfolio · 3 funds · growth, tech · FinTech"
  def to_s
    scope = []
    scope << "#{fund_ids.size} #{'fund'.pluralize(fund_ids.size)}" if fund_ids.any?
    scope << "#{portfolio_company_ids.size} #{'company'.pluralize(portfolio_company_ids.size)}" if portfolio_company_ids.any?
    scope << portfolio_companies_tags                                                        if portfolio_companies_tags.present?
    scope << sectors.join(", ")                                                              if sectors.any?
    scope = ["All"] if scope.empty?
    "#{run_type.humanize} · #{scope.join(' · ')}"
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[end_date run_type currency portfolio_companies_tags fund_ids portfolio_company_ids sectors created_at anchor_fund_id user_id entity_id fund_ratio_run_template_id].sort
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[anchor_fund user]
  end

  def source_funds
    Fund.where(id: fund_ids)
  end

  def source_portfolio_companies
    Investor.where(id: portfolio_company_ids)
  end

  # Returns the resolved set of portfolio companies a run processes.
  #
  # Rules:
  #   - Explicit IDs are always included regardless of other filters.
  #   - Tags alone  → union in all companies matching any tag.
  #   - Sectors alone → union in all companies matching any sector.
  #   - Tags AND sectors together → intersect: company must match at least one tag AND be in at least one sector.
  #   - All of the above are OR'd with the explicit ID set.
  #   - Returns nil when no filter is set (meaning "all portfolio companies — no scoping").
  def resolved_portfolio_companies
    pc_ids = Set.new
    pc_ids.merge(portfolio_company_ids.map(&:to_i)) if portfolio_company_ids.any?

    if portfolio_companies_tags.present? && sectors.any?
      # AND: company must satisfy both the tag filter and the sector filter.
      tag_ids    = entity.investors.portfolio_companies.with_any_tags(portfolio_companies_tags).pluck(:id)
      sector_ids = entity.investors.portfolio_companies.in_sector(sectors).pluck(:id)
      pc_ids.merge(tag_ids & sector_ids)
    elsif portfolio_companies_tags.present?
      pc_ids.merge(entity.investors.portfolio_companies.with_any_tags(portfolio_companies_tags).pluck(:id))
    elsif sectors.any?
      pc_ids.merge(entity.investors.portfolio_companies.in_sector(sectors).pluck(:id))
    end

    return entity.investors.where(id: pc_ids.to_a) if pc_ids.any?

    # Filters were specified but nothing matched (e.g. tags ∩ sectors is empty, or tag
    # has no matching companies). Return an empty relation — NOT nil — so callers get
    # zero results rather than silently falling back to "all portfolio companies".
    filters_specified = portfolio_company_ids.any? || portfolio_companies_tags.present? || sectors.any?
    filters_specified ? entity.investors.none : nil
  end

  # Finds the FundRatioRunTemplate that produced this run by matching its
  # fingerprint. Returns nil if no template matches (e.g. ad-hoc runs).
  def template
    FundRatioRunTemplate.where(entity_id: entity_id).find do |t|
      FundRatioRun.fingerprint(
        fund_ids: Array(t.fund_ids).map(&:to_i).reject(&:zero?),
        portfolio_company_ids: t.portfolio_company_ids,
        tags: t.portfolio_companies_tags,
        sectors: t.sectors
      ) == name
    end
  end

  private

  def set_name
    self.name ||= self.class.fingerprint(
      fund_ids: fund_ids,
      portfolio_company_ids: portfolio_company_ids,
      tags: portfolio_companies_tags,
      sectors: sectors,
      type: run_type
    )
  end
end

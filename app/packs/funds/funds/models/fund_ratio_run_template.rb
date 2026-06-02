# Stores a reusable filter configuration that can be dispatched as a
# FundRatiosScenarioJob for any given end_date without re-entering filters.
#
# Each entity has one flat collection of templates (no separate "set" model).
# The optional `tag` field groups templates so a subset can be triggered together.
#
# When #enqueue is called, it fires FundRatiosScenarioJob with the stored params
# plus the caller-supplied end_date. The job then finds-or-creates a FundRatioRun
# via the existing fingerprint mechanism — no new job class is required.
class FundRatioRunTemplate < ApplicationRecord
  # MySQL rejects literal defaults on JSON columns so we declare them in Ruby.
  attribute :fund_ids,              :json, default: -> { [] }
  attribute :portfolio_company_ids, :json, default: -> { [] }
  attribute :sectors,               :json, default: -> { [] }
  attribute :tags,                  :json, default: -> { [] }

  # Set by trigger actions before validation so rules can inspect the trigger date.
  # Not persisted — only meaningful during the enqueue flow.
  attr_accessor :trigger_end_date

  belongs_to :entity
  belongs_to :user
  # anchor_fund mirrors FundRatioRun#anchor_fund — used for document folder
  # resolution and policy scoping only; does not limit which data feeds the calc.
  belongs_to :anchor_fund, class_name: "Fund", optional: true
  has_many :fund_ratio_runs, dependent: :nullify

  VALID_RUN_TYPES = %w[cross-fund cross-portfolio].freeze

  before_validation :infer_run_type

  validates :name,     presence: true, uniqueness: { scope: :entity_id }
  validates :run_type, inclusion: { in: VALID_RUN_TYPES }

  # Ordered by position first so the UI respects user-set ordering, then by name
  # as a stable fallback when positions are equal or nil.
  scope :ordered,    -> { order(Arel.sql("COALESCE(position, 999999)"), :name) }
  scope :for_entity, ->(entity_id) { where(entity_id:) }

  # Filters templates that include the given tag in their tags JSON array.
  # Uses MEMBER OF (MySQL 8+) or json_each (SQLite in tests).
  scope :for_tag, ->(tag) {
    if connection.adapter_name.downcase.include?("sqlite")
      where("EXISTS (SELECT 1 FROM json_each(fund_ratio_run_templates.tags) WHERE value = ?)", tag)
    else
      where("? MEMBER OF (tags)", tag)
    end
  }

  # Returns all distinct non-blank tags across the relation, sorted.
  # Loaded in Ruby because extracting values from a JSON array in SQL
  # requires json_each / JSON_TABLE which varies by adapter.
  def self.distinct_tags
    pluck(:tags).flatten.compact.map(&:strip).reject(&:blank?).uniq.sort
  end

  # Returns all FundRatioRun records produced by triggering this template.
  # Matched by fingerprint — the same hash the job computes from the stored filters.
  private

  # Infer run_type from the filter fields so the user never has to set it manually.
  # Any portfolio-company filter (explicit IDs, tags, or sectors) → cross-portfolio.
  # Fund IDs only → cross-fund.
  def infer_run_type
    self.run_type = if portfolio_company_ids.any? || portfolio_companies_tags.present? || sectors.any?
                      "cross-portfolio"
                    else
                      "cross-fund"
                    end
  end

  public

  def runs
    fund_ratio_runs.order(end_date: :desc)
  end

  # Enqueues FundRatiosScenarioJob for this template with the given end_date.
  # anchor_fund_id may be nil — the job accepts nil and leaves anchor_fund blank on
  # the run, which is allowed (anchor_fund is optional on FundRatioRun).
  def enqueue(end_date:, user_id:)
    FundRatiosScenarioJob.perform_later(
      anchor_fund_id,
      end_date,
      user_id,
      fund_ids:                    fund_ids.presence,
      portfolio_company_ids:       portfolio_company_ids.presence,
      portfolio_companies_tags:    portfolio_companies_tags.presence,
      portfolio_companies_sectors: sectors.presence,
      currency:                    currency.presence,
      type:                        run_type,
      template_id:                 id
    )
  end
end

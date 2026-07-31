# frozen_string_literal: true

# Defines what KPIs to track per portfolio company, including name translation,
# parent-child hierarchy, data types, denominations, and FX conversion method.
# @see Kpi
# @see KpiReport
class InvestorKpiMapping < ApplicationRecord
  include WithCustomField

  has_ancestry

  HIGHLIGHT_KPI_CF = "highlight_kpi"

  belongs_to :entity
  belongs_to :investor
  acts_as_list scope: :investor, add_new_at: :bottom
  default_scope { order(:position) }

  attribute :rag_rules, :json, default: {}

  has_one :investor_entity, class_name: "Entity", through: :investor
  has_many :kpis, through: :investor_entity
  CATEGORIES = ["Balance Sheet", "Income Statement", "Cashflow Statement", "Operational Metrics", "Other"].freeze
  validates :category, length: { maximum: 40 }, allow_blank: true

  scope :show_in_report, -> { where(show_in_report: true) }

  validates :reported_kpi_name, :standard_kpi_name, length: { maximum: 100 }

  enum :data_type, { money: 'money', numeric: 'numeric', percentage: 'percentage' }
  enum :denomination, { millions: 'millions', crores: 'crores', lakhs: 'lakhs', thousands: 'thousands' }
  enum :autofill, { cumulate: 'cumulate', forward_fill: 'forward_fill', compute: 'compute' }, prefix: true
  FX_CONVERSION_METHODS = %w[not_applicable report_date average_rate].freeze
  enum :fx_conversion_method, {
    not_applicable: 'not_applicable',
    report_date: 'report_date',
    average_rate: 'average_rate'
  }, default: :not_applicable, prefix: :fx

  scope :cumulate, -> { where(autofill: 'cumulate') }
  scope :forward_fill, -> { where(autofill: 'forward_fill') }
  scope :compute, -> { where(autofill: 'compute') }
  scope :not_compute, -> { where(autofill: [nil, 'cumulate', 'forward_fill']) }

  before_create :setup_standard_kpi_name
  def setup_standard_kpi_name
    self.reported_kpi_name = reported_kpi_name.strip
    self.standard_kpi_name = reported_kpi_name if standard_kpi_name.blank?
    self.standard_kpi_name = standard_kpi_name.strip
  end

  # @return [void]
  before_validation :set_default_fx_conversion_method, on: :create

  # Sets IAS 21-aligned FX conversion default based on KPI category.
  # Percentage KPIs are always not_applicable (25% is 25% in any currency).
  # @return [void]
  def set_default_fx_conversion_method
    return if fx_conversion_method_changed?
    return self.fx_conversion_method = 'not_applicable' if percentage?

    self.fx_conversion_method = case category
                                when 'Income Statement', 'Cashflow Statement'
                                  'average_rate'
                                when 'Balance Sheet'
                                  'report_date'
                                else
                                  'not_applicable'
                                end
  end

  validate :formula_kosher?
  def formula_kosher?
    return false if compute_formula.blank?

    errors.add(:compute_formula, "You cannot do CRUD operations in a formula") if compute_formula.downcase.match?(SAFE_EVAL_REGEX)
  end

  # @return [void]
  validate :fx_not_applicable_for_percentages

  # Ensures percentage KPIs are never currency-converted (25% is 25% in any currency).
  # @return [void]
  def fx_not_applicable_for_percentages
    return unless percentage? && !fx_not_applicable?

    errors.add(:fx_conversion_method, "must be 'Not Applicable' for percentage KPIs")
  end

  after_commit :update_parent_child_count
  def update_parent_child_count
    parent&.update(child_count: parent.children.count)
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[reported_kpi_name standard_kpi_name category]
  end

  def self.create_from(entity, kpi_report)
    investor = if kpi_report && kpi_report.portfolio_company_id.present?
                 kpi_report.portfolio_company
               else
                 entity.investors.where(investor_entity_id: kpi_report.entity_id).first
               end
    kpi_report.kpis.each do |kpi|
      ikm = InvestorKpiMapping.find_or_initialize_by(entity:, investor:, reported_kpi_name: kpi.name, standard_kpi_name: kpi.name)
      if ikm.new_record?
        ikm.show_in_report = true
        ikm.save
      end
    end
  end

  def to_s
    reported_kpi_name
  end
end

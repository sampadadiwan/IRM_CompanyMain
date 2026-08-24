class Kpi < ApplicationRecord
  include WithCustomField
  include ForInvestor
  include Trackable.new(on: %i[create update], audit_fields: %i[value display_value notes percentage_change])
  include KpiCumulative

  enum :status, { unapproved: 'unapproved', approved: 'approved' }, default: :approved

  STANDARD_COLUMNS = {
    "Name; text-col" => "name; text-col",
    "Value; num-col" => "value; num-col",
    "Display Value; text-col" => "display_value; text-col",
    "Percentage Change; num-col" => "percentage_change; num-col",
    "Notes; text-col" => "notes; text-col"
  }.freeze

  ADDITIONAL_COLUMNS_FROM = %i[kpi_report investor_kpi_mapping].freeze

  belongs_to :entity
  belongs_to :owner, class_name: "Entity", optional: true
  belongs_to :portfolio_company, class_name: "Investor", optional: true
  # These are the investees, who will probably have investor_kpi_mappings for the kpis by this entity.
  has_many :investees, through: :entity

  belongs_to :kpi_report
  belongs_to :investor_kpi_mapping, optional: true
  belongs_to :approved_by, class_name: "User", foreign_key: :approved_by_user_id, optional: true

  validates :name, :value, presence: true

  validates :name, length: { maximum: 100 }
  validates :notes, length: { maximum: 255 }
  validates :display_value, length: { maximum: 30 }
  validates :source, length: { maximum: 100 }, allow_blank: true

  validates :status, presence: true
  validates :name, uniqueness: { scope: %i[kpi_report_id portfolio_company_id status deleted_at] }, if: -> { approved? }

  # KPIs created before this date predate mapping-id assignment (backfilled by the workbook job),
  # so they're exempt. Everything created on or after it must carry an investor_kpi_mapping_id.
  # A fixed cutoff (not Date.current) so a record's exemption never flips as days pass.
  MAPPING_ID_REQUIRED_FROM = Date.new(2026, 7, 24)
  validates :investor_kpi_mapping_id, presence: true, if: :require_mapping_id?

  scope :no_tag_list, -> { joins(:kpi_report).where('kpi_reports.tag_list': nil) }
  # --- Generic filters -------------------------------------------------
  scope :for_metric,  ->(name)  { where(name:) }
  scope :for_company, ->(pc_id) { where(portfolio_company_id: pc_id) }
  scope :approved,   -> { where(status: :approved) }
  scope :unapproved, -> { where(status: :unapproved) }
  scope :actuals,    -> { joins(:kpi_report).where('kpi_reports.tag_list': 'Actual') }
  scope :budgets,    -> { joins(:kpi_report).where('kpi_reports.tag_list': 'Budget') }
  scope :ics,        -> { joins(:kpi_report).where('kpi_reports.tag_list': 'IC') }
  scope :as_of,      ->(date) { joins(:kpi_report).where('kpi_reports.as_of': date) }
  scope :show_in_report, -> { joins(:investor_kpi_mapping).where(investor_kpi_mappings: { show_in_report: true }) }

  scope :monthly, -> { joins(:kpi_report).where(kpi_reports: { period: 'month' }) }
  scope :quarterly, -> { joins(:kpi_report).where(kpi_reports: { period: 'quarter' }) }
  scope :yearly, -> { joins(:kpi_report).where(kpi_reports: { period: 'year' }) }
  scope :ytd, -> { joins(:kpi_report).where(kpi_reports: { period: 'ytd' }) }

  # --- Scopes needing joins -------------------------------------------
  # Attach the parent report so date filters hit SQL, not Ruby.
  scope :with_report, -> { joins(:kpi_report) }

  scope :cumulate, -> { joins(:investor_kpi_mapping).where(investor_kpi_mappings: { autofill: :cumulate }) }
  scope :forward_fill, -> { joins(:investor_kpi_mapping).where(investor_kpi_mappings: { autofill: :forward_fill }) }
  scope :compute, -> { joins(:investor_kpi_mapping).where(investor_kpi_mappings: { autofill: :compute }) }

  # --- Time helpers ----------------------------------------------------
  scope :for_date, lambda { |date|
    with_report.where(kpi_reports: { as_of: date })
  }

  scope :in_date_range, lambda { |range|
    with_report.where(kpi_reports: { as_of: range })
  }

  def custom_form_field
    field = nil
    if kpi_report.form_type
      sanitized_name = name.downcase.strip
      field = kpi_report.form_type.form_custom_fields.where(name: sanitized_name).first
      if field.nil?
        kpi_report.form_type.form_custom_fields.where("meta_data like '%#{sanitized_name}%'").find_each do |fcf|
          field = fcf if fcf.meta_data.downcase.split(",").include?(sanitized_name)
        end
      end
    end
    field ||= FormCustomField.new(field_type: "TextField", name:)
    field
  end

  def to_s
    "#{name}: #{value}"
  end

  # New records (created_at nil until saved) and anything created on/after the cutoff must have a
  # mapping id; legacy KPIs created before it are grandfathered in.
  def require_mapping_id?
    (created_at || Time.current) >= MAPPING_ID_REQUIRED_FROM.beginning_of_day
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[name value notes percentage_change portfolio_company_id status updated_at category].sort.freeze
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[kpi_report entity investor_kpi_mapping portfolio_company]
  end

  def kpis_for_entity
    entity.kpis.joins(:kpi_report).where(name:).where("kpi_reports.period=?", kpi_report.period).order("kpi_reports.as_of asc")
  end

  def self.recompute_percentage_change(kpis, force: false)
    # Group KPIs by period, name, and tag_list to ensure percentage is only computed between comparable KPIs
    kpis.group_by { |kpi| [kpi.kpi_report.period, kpi.name, kpi.kpi_report.tag_list] }.each_value do |grouped_kpis|
      grouped_kpis.sort_by { |kpi| kpi.kpi_report.as_of }.each_cons(2) do |current_kpi, next_kpi|
        next unless force || next_kpi.percentage_change.nil? || next_kpi.percentage_change.zero?

        next_kpi.percentage_change = if current_kpi.value.zero?
                                       # if the divisor (the current) is 0, the percentage is infinity but we cant store that so keeping it nil
                                       nil
                                     else
                                       ((next_kpi.value - current_kpi.value) / current_kpi.value) * 100
                                     end
        next_kpi.save
      end
    end
  end

  # Method to find the tagged KPI
  def find_tagged_kpi(tag_list)
    Kpi.joins(:kpi_report)
       .where(
         name: name,
         portfolio_company_id: portfolio_company_id,
         'kpi_reports.as_of': kpi_report.as_of,
         'kpi_reports.tag_list': tag_list # Match by tag_list
       )
       .first
  end

  # Live RAG computation — see docs/technical/kpi_rag_rules_redesign.md (Phase 3). Recomputes
  # whenever a value is saved, and cascades to same-name/date siblings so a comparator (e.g.
  # Budget) entered after the actual still triggers the actual's status to update.
  after_save :recompute_rag_status!, if: :saved_change_to_value?
  after_save :recompute_dependent_rag_statuses!, if: :saved_change_to_value?

  def recompute_rag_status!
    mapping = investor_kpi_mapping
    return unless mapping&.rag_configured?

    comparator_value = nil
    if mapping.rag_comparator_tag.present?
      comparator = find_tagged_kpi(mapping.rag_comparator_tag)
      comparator = nil if comparator&.id == id # comparing a value to itself isn't meaningful
      comparator_value = comparator&.value
    end

    new_status = RagStatusEvaluator.call(value: value, comparator_value: comparator_value, mapping: mapping)[:status]
    update_column(:rag_status, new_status) if new_status != rag_status
  end

  def recompute_dependent_rag_statuses!
    Kpi.joins(:kpi_report)
       .where(name: name, portfolio_company_id: portfolio_company_id, 'kpi_reports.as_of': kpi_report.as_of)
       .where.not(id: id)
       .find_each(&:recompute_rag_status!)
  end
end

class Kpi < ApplicationRecord
  include WithCustomField
  include ForInvestor

  belongs_to :entity
  belongs_to :owner, class_name: "Entity", optional: true
  belongs_to :portfolio_company, class_name: "Investor", optional: true
  # These are the investees, who will probably have investor_kpi_mappings for the kpis by this entity.
  has_many :investees, through: :entity
  # This is for ransack search only. For some reason crashes on single kpi instance
  has_many :investor_kpi_mappings, -> { where("`investor_kpi_mappings`.`standard_kpi_name`=`kpis`.`name`") }, through: :investees

  belongs_to :kpi_report

  validates :name, :value, presence: true

  validates :name, length: { maximum: 50 }
  validates :notes, length: { maximum: 255 }
  validates :display_value, length: { maximum: 30 }

  scope :no_tag_list, -> { joins(:kpi_report).where('kpi_reports.tag_list': nil) }
  # --- Generic filters -------------------------------------------------
  scope :for_metric,  ->(name)  { where(name:) }
  scope :for_company, ->(pc_id) { where(portfolio_company_id: pc_id) }

  # Attach the parent report so date filters hit SQL, not Ruby.
  scope :with_report, -> { joins(:kpi_report) }

  # --- Time helpers ----------------------------------------------------
  scope :for_date, lambda { |date|
    with_report.where(kpi_reports: { as_of: date })
  }

  scope :in_date_range, lambda { |range|
    with_report.where(kpi_reports: { as_of: range })
  }

  scope :monthly, -> { where(kpi_reports: { period: 'month' }) }

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

  def self.ransackable_attributes(_auth_object = nil)
    %w[name value notes percentage_change]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[kpi_report entity investor_kpi_mappings portfolio_company]
  end

  def kpis_for_entity
    entity.kpis.joins(:kpi_report).where(name:).where("kpi_reports.period=?", kpi_report.period).order("kpi_reports.as_of asc")
  end

  def self.recompute_percentage_change(kpis)
    # Get all the kpis for the entity with same name and period
    kpis.each_cons(2) do |current_kpi, next_kpi|
      if next_kpi.percentage_change.nil? || next_kpi.percentage_change.zero?
        next_kpi.percentage_change = ((next_kpi.value - current_kpi.value) / current_kpi.value) * 100
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

  # Helper method to determine RAG status from rules
  def determine_rag_status_from_rules(ratio, rules_hash, comparison_type: 'ratio_rules')
    return nil unless rules_hash.present? && rules_hash[comparison_type].present?

    rules = rules_hash[comparison_type]

    # Convert string keys to symbols for easier access if needed, or ensure consistency
    # rules = rules.transform_keys(&:to_sym)

    # Sort rules by min bound to ensure correct order of evaluation
    sorted_rules = rules.values.sort_by { |r| r['min'] }

    sorted_rules.each do |rule|
      min_val = rule['min'] == '-Infinity' ? -Float::INFINITY : rule['min'].to_f
      max_val = rule['max'] == 'Infinity' ? Float::INFINITY : rule['max'].to_f

      if ratio >= min_val && ratio < max_val
        # Find the key (rag_status name) that corresponds to this rule's values
        return rules.key(rule)
      end
    end
    nil # No matching status found
  end

  # Method to compute and set RAG status
  def set_rag_status_from_ratio(tagged_kpi_tag_list)
    tagged_kpi = find_tagged_kpi(tagged_kpi_tag_list)

    # Find the InvestorKpiMapping for this KPI's standard name
    # Kpi.name will match InvestorKpiMapping.standard_kpi_name
    investor_kpi_mapping = InvestorKpiMapping.find_by(standard_kpi_name: name)

    if tagged_kpi && tagged_kpi.value.present? && tagged_kpi.value != 0 && investor_kpi_mapping&.rag_rules.present?
      ratio = value.to_f / tagged_kpi.value
      self.rag_status = determine_rag_status_from_rules(ratio, investor_kpi_mapping.rag_rules)
    elsif tagged_kpi && tagged_kpi.value.present? && tagged_kpi.value.zero?
      # Handle division by zero: perhaps set to 'red' or a specific status for this case
      self.rag_status = 'red' # Or 'N/A', 'undefined', based on business logic
    else
      self.rag_status = nil # Or a default status if tagged_kpi or rules are not found
    end
    save if changed? # Save the KPI if rag_status has been updated
  end
end

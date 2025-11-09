class Kpi < ApplicationRecord
  include WithCustomField
  include ForInvestor
  include Trackable.new(on: %i[create update], audit_fields: %i[value display_value notes percentage_change])

  belongs_to :entity
  belongs_to :owner, class_name: "Entity", optional: true
  belongs_to :portfolio_company, class_name: "Investor", optional: true
  # These are the investees, who will probably have investor_kpi_mappings for the kpis by this entity.
  has_many :investees, through: :entity

  belongs_to :kpi_report
  belongs_to :investor_kpi_mapping, optional: true

  validates :name, :value, presence: true

  validates :name, length: { maximum: 50 }
  validates :notes, length: { maximum: 255 }
  validates :display_value, length: { maximum: 30 }

  scope :no_tag_list, -> { joins(:kpi_report).where('kpi_reports.tag_list': nil) }
  # --- Generic filters -------------------------------------------------
  scope :for_metric,  ->(name)  { where(name:) }
  scope :for_company, ->(pc_id) { where(portfolio_company_id: pc_id) }
  scope :actuals,    -> { joins(:kpi_report).where('kpi_reports.tag_list': 'Actual') }
  scope :budgets,    -> { joins(:kpi_report).where('kpi_reports.tag_list': 'Budget') }
  scope :ics,        -> { joins(:kpi_report).where('kpi_reports.tag_list': 'IC') }

  # --- Scopes needing joins -------------------------------------------
  # Attach the parent report so date filters hit SQL, not Ruby.
  scope :with_report, -> { joins(:kpi_report) }
  scope :cumulatable, -> { joins(:investor_kpi_mapping).where(investor_kpi_mappings: { cumulate: true }) }

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
    %w[kpi_report entity investor_kpi_mapping portfolio_company]
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
    Rails.logger.debug { "Kpi:  set_rag_status_from_ratio called for KPI: #{name}, value: #{value}, report_as_of: #{kpi_report.as_of}, pc_id: #{portfolio_company_id}" }
    Rails.logger.debug { "Kpi:  Looking for tagged KPI with tag: #{tagged_kpi_tag_list}" }

    tagged_kpi = find_tagged_kpi(tagged_kpi_tag_list)

    Rails.logger.debug { "Kpi:  Found tagged_kpi: #{tagged_kpi.present? ? tagged_kpi.to_s : 'nil'}" }
    Rails.logger.debug { "Kpi:  tagged_kpi.value: #{tagged_kpi&.value}" }
    Rails.logger.debug { "Kpi:  investor_kpi_mapping&.rag_rules.present?: #{investor_kpi_mapping&.rag_rules.present?}" }

    if tagged_kpi && tagged_kpi.value.present? && tagged_kpi.value != 0 && investor_kpi_mapping&.rag_rules.present?
      ratio = value.to_f / tagged_kpi.value
      self.rag_status = determine_rag_status_from_rules(ratio, investor_kpi_mapping.rag_rules)
      Rails.logger.debug { "Kpi:  RAG status determined: #{rag_status}" }
    elsif tagged_kpi && tagged_kpi.value.present? && tagged_kpi.value.zero?
      self.rag_status = 'red'
      Rails.logger.debug "--- RAG status set to 'red' due to division by zero."
    else
      self.rag_status = nil
      Rails.logger.debug "--- RAG status set to nil (conditions not met)."
    end
    save if changed?
  end

  # This is used to cumulate the KPI values over time periods like Quarterly and YTD
  def cumulate
    Rails.logger.info "--- [#{name}] Starting cumulate for KPI '#{name}' for entity #{entity_id}, pc_id: #{portfolio_company_id}"

    # Find all related monthly KPIs for this entity and name, but only Actuals
    related_kpis = entity.kpis.joins(:kpi_report).includes(:kpi_report)
                         .where(name:, portfolio_company_id:, kpi_reports: { tag_list: 'Actual', period: 'Month' })
                         .order("kpi_reports.as_of ASC")

    Rails.logger.info "--- [#{name}] Found #{related_kpis.size} related monthly KPIs"
    return if related_kpis.empty?

    # Group KPIs by year and quarter to calculate sums efficiently
    kpis_by_quarter = related_kpis.group_by { |kpi| [kpi.kpi_report.as_of.year, ((kpi.kpi_report.as_of.month - 1) / 3) + 1] }
    kpis_by_year = related_kpis.group_by { |kpi| kpi.kpi_report.as_of.year }

    # Process each quarter's cumulative value once
    kpis_by_quarter.each do |(year, quarter), kpis_in_quarter|
      quarterly_sum = kpis_in_quarter.sum { |kpi| kpi.value.to_f }
      last_kpi_in_quarter = kpis_in_quarter.last
      quarter_start = Date.new(year, ((quarter - 1) * 3) + 1, 1)
      quarter_end = quarter_start.end_of_quarter
      process_cumulative_kpi(last_kpi_in_quarter, quarterly_sum, 'Quarter', quarter_start, quarter_end)
    end

    # Process each year's cumulative value once
    kpis_by_year.each do |year, kpis_in_year|
      ytd_sum = kpis_in_year.sum { |kpi| kpi.value.to_f }
      last_kpi_in_year = kpis_in_year.last
      year_start = Date.new(year, 1, 1)
      year_end = Date.new(year, 12, 31)
      process_cumulative_kpi(last_kpi_in_year, ytd_sum, 'YTD', year_start, year_end)
    end

    Rails.logger.info "--- [#{name}] Cumulate complete for KPI '#{name}'"
  end

  private

  def process_cumulative_kpi(monthly_kpi, cumulative_sum, period, start_date, end_date)
    Rails.logger.debug { "Kpi:  [#{name}] Processing #{period} KPI for #{start_date} to #{end_date}, cumulative sum: #{cumulative_sum}" }

    cumulative_kpi = Kpi.joins(:kpi_report)
                        .where(entity_id: entity_id, name:, portfolio_company_id: portfolio_company_id)
                        .where(kpi_reports: { period: period })
                        .where("kpi_reports.as_of BETWEEN ? AND ?", start_date, end_date)
                        .last

    if cumulative_kpi
      Rails.logger.debug { "Kpi:  [#{name}] Existing #{period} KPI found (id=#{cumulative_kpi.id}), current value=#{cumulative_kpi.value}, new value=#{cumulative_sum}" }
      cumulative_kpi.value = cumulative_sum
      cumulative_kpi.notes = "Auto-generated #{period} cumulative"
      if cumulative_kpi.changed?
        Rails.logger.info "--- [#{name}] Overwriting #{period} KPI #{cumulative_kpi.id} with new value #{cumulative_sum}"
        cumulative_kpi.save
      else
        Rails.logger.debug { "Kpi:  [#{name}] Skipping save for #{period} KPI #{cumulative_kpi.id} (unchanged)" }
      end

    else
      Rails.logger.info "--- [#{name}] Creating new #{period} KPI with value #{cumulative_sum}"
      user_id = monthly_kpi.kpi_report.user_id

      kpi_report = KpiReport.find_or_create_by(period: period, as_of: monthly_kpi.kpi_report.as_of,
                                               entity_id:, portfolio_company_id:, user_id:)

      kpi = Kpi.find_or_initialize_by(entity_id:, name:, portfolio_company_id:, kpi_report:)
      kpi.value = cumulative_sum
      kpi.notes = "Auto-generated #{period} cumulative"
      kpi.save
    end
  end
end

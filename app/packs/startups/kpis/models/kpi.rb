class Kpi < ApplicationRecord
  include WithCustomField
  include ForInvestor

  belongs_to :entity
  belongs_to :owner, class_name: "Entity", optional: true
  belongs_to :portfolio_company, class_name: "Investor", optional: true
  # These are the investees, who will probably have investor_kpi_mappings for the kpis by this entity.
  has_many :investees, through: :entity
  # This is for ransack search only. For some reason crashes on single kpi instance
  has_many :investor_kpi_mappings, -> { where("`investor_kpi_mappings`.`reported_kpi_name`=`kpis`.`name`") }, through: :investees

  belongs_to :kpi_report

  validates :name, :value, presence: true

  validates :name, length: { maximum: 50 }
  validates :notes, length: { maximum: 255 }
  validates :display_value, length: { maximum: 30 }

  scope :no_tag_list, -> { joins(:kpi_report).where('kpi_reports.tag_list': nil) }

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
    %w[kpi_report entity investor_kpi_mappings]
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
end

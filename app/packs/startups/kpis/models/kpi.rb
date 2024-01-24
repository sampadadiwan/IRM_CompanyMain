class Kpi < ApplicationRecord
  include WithCustomField
  include ForInvestor

  belongs_to :entity
  belongs_to :kpi_report

  validates :name, :period, :value, presence: true

  validates :name, length: { maximum: 50 }
  validates :period, length: { maximum: 12 }
  validates :notes, length: { maximum: 255 }
  validates :display_value, length: { maximum: 30 }

  def custom_form_field
    sanitized_name = name.downcase.strip
    field = kpi_report.form_type.form_custom_fields.where(name: sanitized_name).first
    if field.nil?
      kpi_report.form_type.form_custom_fields.where("meta_data like '%#{sanitized_name}%'").find_each do |fcf|
        field = fcf if fcf.meta_data.downcase.split(",").include?(sanitized_name)
      end
    end
    field ||= FormCustomField.new(field_type: "Unknown", name:)
    field
  end

  def to_s
    "#{name}: #{value}"
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[name period value notes]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[kpi_report entity]
  end

  # Note the input kpis must have the same name, this is not checked inside the method
  # Returns an array of growth rates, the average growth rate and an array of values used in the growth rate calculation
  def self.calculate_growth_rates(kpis)
    growth_rates = []
    cagr = 0
    values = []

    kpis.each_cons(2) do |current, previous|
      values << current.value
      growth_rate = ((current.value - previous.value) / previous.value) * 100
      growth_rates << growth_rate
      cagr += growth_rate
    end

    [growth_rates, (growth_rates.sum / kpis.length), values]
  end
end

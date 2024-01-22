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

  def self.ransackable_attributes(_auth_object = nil)
    %w[name period value notes]
  end

  def self.ransackable_associations(_auth_object = nil)
    ["kpi_report"]
  end
end

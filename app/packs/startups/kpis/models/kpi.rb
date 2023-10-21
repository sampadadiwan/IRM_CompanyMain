class Kpi < ApplicationRecord
  include WithCustomField

  belongs_to :entity
  belongs_to :kpi_report

  validates :name, length: { maximum: 50 }
  validates :display_value, length: { maximum: 30 }

  def custom_form_field
    field = kpi_report.form_type.form_custom_fields.where(name: name.downcase).first
    if field.nil?
      kpi_report.form_type.form_custom_fields.where("meta_data like '%#{name.downcase}%'").find_each do |fcf|
        field = fcf if fcf.meta_data.downcase.split(",").include?(name.downcase)
      end
    end
    field ||= FormCustomField.new(field_type: "Unknown", name:)
    field
  end
end

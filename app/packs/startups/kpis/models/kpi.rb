class Kpi < ApplicationRecord
  include WithCustomField

  belongs_to :entity
  belongs_to :kpi_report

  validates :name, length: { maximum: 50 }
  validates :display_value, length: { maximum: 30 }
end

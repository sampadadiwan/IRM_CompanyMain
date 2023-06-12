class Kpi < ApplicationRecord
  include WithCustomField

  belongs_to :entity
  belongs_to :kpi_report
end

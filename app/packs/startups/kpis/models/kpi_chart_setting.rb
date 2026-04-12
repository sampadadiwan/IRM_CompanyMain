class KpiChartSetting < ApplicationRecord
  belongs_to :user
  belongs_to :entity
  belongs_to :portfolio_company, class_name: "Investor", optional: true

  validates :name, presence: true
  validates :config, presence: true

  # config expected format: [{ "name": "KPI Name", "type": "line|column|pie|donut|area" }, ...]
end

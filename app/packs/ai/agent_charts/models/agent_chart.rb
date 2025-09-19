class AgentChart < ApplicationRecord
  belongs_to :entity
  belongs_to :owner, polymorphic: true, optional: true

  # Report, which can give the json data for this chart
  belongs_to :report, optional: true

  # List of documents (csv) from which to get the data for the charts
  serialize :document_ids

  STATUSES = %w[draft ready failed].freeze
  validates :status, inclusion: { in: STATUSES }

  def to_s
    title || "AgentChart ##{id}"
  end

  def generate_spec!(csv_paths: [])
    if csv_paths.empty? && document_ids.present?
      # Load CSV paths from associated documents if not explicitly provided
      documents.each do |doc|
        file = doc.file.download
        csv_paths << file.path if file&.path&.end_with?(".csv")
      end
    end
    update!(status: "draft", error: nil)
    spec_hash = ChartAgentService.new(json_data: raw_data, csv_paths:).generate_chart!(prompt: prompt)
    update!(spec: spec_hash, status: "ready")
  rescue StandardError => e
    update!(status: "failed", error: "#{e.class}: #{e.message}")
    raise
  end

  def get_report_data
    if report_id.present? && report.present?
      # We need to make an api call, but as the user
      u = entity.employees.company_admins.first
      Rails.logger.debug { "No company admin user found for entity #{entity_id}, cannot fetch report data" } if u.blank?
    else
      Rails.logger.debug "No report associated with this chart"
    end
  end

  def documents
    Document.where(id: document_ids) if document_ids.present?
  end

  def document_ids=(ids)
    super(ids.is_a?(Array) ? ids.map(&:to_i) : ids.to_s.split(",").map { |x| x.strip.to_i }
  end

  def self.test(csv_paths:)
    charts = [
      "Revenue by Product Line (stacked area) – shows how each product contributes to total sales over time",
      "COGS vs. Gross Profit (line chart) – highlights cost efficiency and profitability trends",
      "Operating Expense Breakdown (stacked bar) – compares R&D vs. SG&A over months",
      "EBITDA, EBIT, and Net Income (multi-line) – visualizes profitability at different stages",
      "Cash Flow Waterfall (CFO, CapEx, FCF) – illustrates how cash is generated and spent",
      "Cash vs. Debt Levels (line chart) – tracks liquidity and leverage over time",
      "Working Capital Components (AR, AP, Inventory line chart) – shows operational efficiency shifts",
      "Margins % (gross, operating, net line chart) – productivity insights",
      "EPS Growth (bar chart) – per-share earnings performance",
      "Headcount vs. Revenue per Employee (dual-axis line chart) – productivity insights"
    ]

    charts.each do |chart_prompt|
      AgentChart.create!(entity_id: 17, status: "draft", title: Faker::Company.catch_phrase, prompt: chart_prompt).generate_spec!(csv_paths: csv_paths)
    end
  end
end

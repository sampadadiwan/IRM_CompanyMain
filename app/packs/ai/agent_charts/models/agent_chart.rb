class AgentChart < ApplicationRecord
  belongs_to :entity
  belongs_to :owner, polymorphic: true, optional: true

  # Report, which can give the json data for this chart
  belongs_to :report, optional: true

  # List of documents (csv) from which to get the data for the charts
  serialize :document_names
  serialize :kpi_names

  STATUSES = %w[draft ready failed].freeze
  validates :status, inclusion: { in: STATUSES }

  scope :with_tag_list, lambda { |tags|
    tags = tags.split(",").map(&:strip) unless tags.is_a?(Array)

    where(
      tags.map { "tag_list LIKE ?" }.join(" OR "),
      *tags.map { |t| "%#{t}%" }
    )
  }

  def to_s
    title || "AgentChart ##{id}"
  end

  def generate_spec!(portfolio_company_id:, csv_paths: [], kpis: [])
    owner = nil
    # This comes from the AgentChart definition
    kpis = kpi_names if kpis.empty?

    # For each document, download the CSV if not already provided
    if csv_paths.empty? && document_names.present?
      # Load CSV paths from associated documents if not explicitly provided
      documents(portfolio_company_id).each do |doc|
        owner = doc.owner
        file = doc.file.download
        csv_paths << file.path if file&.path&.end_with?(".csv")
      end
    end

    # Update status to draft while generating
    update!(status: "draft", error: nil, owner: owner)
    raw_data = get_kpis(portfolio_company_id, kpis: kpis) if kpis.present?

    if csv_paths.present? || raw_data.present?
      spec_hash = ChartAgentService.new(json_data: raw_data, csv_paths:).generate_chart!(prompt: prompt)
      spec ||= {}
      spec[portfolio_company_id] = spec_hash
      update!(spec: spec, status: "ready")
    else
      raise "No data sources (CSV files or KPIs) available to generate chart for portfolio company #{portfolio_company_id}"
    end
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

  def documents(portfolio_company_id)
    Document.where(owner_id: portfolio_company_id, owner_type: "Investor", name: document_names) if document_names.present?
  end

  def document_names=(names)
    self[:document_names] = names.is_a?(Array) ? names.map(&:to_s) : names.to_s.split(",").map(&:strip)
  end

  def get_kpis(portfolio_company_id, kpis:)
    self.kpi_before ||= 12
    self.kpi_before_period ||= "Month"
    # Fetch KPI data for the specified portfolio company and KPIs
    raw_data = entity.kpis.joins(:kpi_report).for_company(portfolio_company_id)
    # Filter by specified KPIs and  period
    raw_data = raw_data.where(name: kpis, kpi_report: { period: self.kpi_before_period })
    # Order by as_of ascending
    raw_data = raw_data.order("kpi_report.as_of ASC").select("kpis.name, kpis.value, kpi_report.as_of")
    # Limit to the most recent kpi_before entries
    raw_data = raw_data.limit(self.kpi_before)

    # We only need name and value for data to be sent as part of the prompt for the AI to generate the chart spec
    raw_data = raw_data.as_json(only: %i[name value as_of]) if kpis.present?
    raw_data
  end
end

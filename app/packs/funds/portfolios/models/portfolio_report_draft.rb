require 'cgi'

class PortfolioReportDraft < ApplicationRecord
  belongs_to :portfolio_company, class_name: "Investor"
  belongs_to :portfolio_report
  belongs_to :portfolio_report_template
  belongs_to :user
  belongs_to :generated_document, class_name: "Document", optional: true

  delegate :entity_id, :entity, to: :portfolio_report

  STATUSES = %w[configuring generating review approved exporting exported].freeze
  KPI_PERIOD_TYPES = KpiReport::PERIODS

  enum :status, STATUSES.index_with(&:itself)

  validates :start_date,      presence: true
  validates :end_date,        presence: true
  validates :kpi_period_type, inclusion: { in: KPI_PERIOD_TYPES }
  validates :kpi_tag,         inclusion: { in: KpiReport::TAG_LIST.values }
  validates :n_periods,       numericality: { greater_than: 0 }
  validate  :end_date_after_start_date

  # Returns the narrative HTML for a section — user edit takes precedence over LLM output.
  # Legacy plain-text content (no leading "<") is auto-upgraded to <ul><li> HTML on read.
  def narrative_for(section_id)
    entry = (section_data || {}).fetch(section_id.to_s, {})
    raw   = entry["user_edit"].presence || entry["llm_output"]
    return nil if raw.blank?

    raw.start_with?("<") ? raw : plain_to_html(raw)
  end

  # Writes LLM output (HTML) for a section without overwriting an existing user edit.
  def set_llm_output(section_id, html)
    self.section_data ||= {}
    section_data[section_id.to_s] ||= {}
    section_data[section_id.to_s]["llm_output"] = html
  end

  # Writes a user override (HTML from Trix) for a section.
  def set_user_edit(section_id, html)
    self.section_data ||= {}
    section_data[section_id.to_s] ||= {}
    section_data[section_id.to_s]["user_edit"] = html
  end

  # Returns the effective KPI grid — user overrides merged on top of DB values.
  def effective_kpi_table
    base      = (kpi_table_data || {}).except("user_overrides")
    overrides = (kpi_table_data || {}).fetch("user_overrides", {})
    base.deep_merge(overrides)
  end

  # Writes a user override for a single KPI cell.
  def override_kpi_cell(metric_id, period_label, value)
    self.kpi_table_data ||= {}
    kpi_table_data["user_overrides"] ||= {}
    kpi_table_data["user_overrides"][metric_id.to_s] ||= {}
    kpi_table_data["user_overrides"][metric_id.to_s][period_label] = value
  end

  def to_s
    "#{portfolio_company} — #{portfolio_report_template} (#{start_date} to #{end_date})"
  end

  private

  def end_date_after_start_date
    return unless start_date && end_date
    errors.add(:end_date, "must be after start date") if end_date <= start_date
  end

  # Converts legacy newline-separated plain text to <ul><li> HTML.
  def plain_to_html(text)
    lines = text.split("\n").map(&:strip).reject(&:empty?)
    return "" if lines.empty?
    "<ul>#{lines.map { |l| "<li>#{CGI.escapeHTML(l)}</li>" }.join}</ul>"
  end
end

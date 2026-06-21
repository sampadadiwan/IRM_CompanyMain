require 'nokogiri'

# Renders a PortfolioReportDraft to .docx bytes using a Sablon «variable» template.
#
# Activated by PortfolioReportExportJob#generate_word when the uploaded style_document
# contains Sablon markers (« or »), detected via has_sablon_placeholders?.
#
# Context keys available inside the Sablon template:
#   «portfolio_company»  — decorated Investor (portco)
#   «report»             — decorated PortfolioReport
#   «template»           — PortfolioReportTemplate (plain AR object)
#   «period»             — "Jan 2025 – Jun 2025" string
#   «start_date»         — Date
#   «end_date»           — Date
#   «current_date»       — "21/06/2026"
#   «sections»           — Array of OpenStructs: .name, .narrative_html, .bullets (Array<String>)
#   «kpis»               — Array of OpenStructs mirroring KPI grid rows (same as PortfolioReportDocGenerator)
#   «cap_table»          — Array of OpenStructs from GenerateCapTable
#   «report_data»        — OpenStruct of latest PortfolioReportExtract JSON for this portco (or nil)
#   «image:logo»         — Sablon image path for portco logo
#   «context»            — DocGenContext debug dump
class PortfolioReportSablonWordService
  include DocumentGeneratorBase
  include ActionView::Helpers::NumberHelper
  include CurrencyHelper

  # Data.define used instead of OpenStruct — keys are known at definition time.
  Section = Data.define(:name, :narrative_html, :bullets)

  attr_accessor :working_dir

  def initialize(draft)
    @draft      = draft
    @portco     = draft.portfolio_company
    @template   = draft.portfolio_report_template
    @report     = draft.portfolio_report
    @start_date = draft.start_date
    @end_date   = draft.end_date
  end

  # Returns the rendered .docx content as a binary String.
  # style_docx_path is the path to the downloaded Sablon template file.
  def generate(style_docx_path)
    create_working_dir(@portco)
    sablon_tmpl = Sablon.template(File.expand_path(style_docx_path))
    context     = build_context
    file_name   = generated_file_name(@portco)
    convert(sablon_tmpl, context, file_name, to_pdf: false, template_name: @template.name)
    File.binread("#{file_name}.docx")
  ensure
    cleanup
  end

  private

  def build_context
    context = {}
    context[:portfolio_company] = TemplateDecorator.decorate(@portco)
    context[:report]            = TemplateDecorator.decorate(@report)
    context[:template]          = @template
    context[:period]            = period_label
    context[:start_date]        = @start_date
    context[:end_date]          = @end_date
    context[:current_date]      = Time.zone.today.strftime('%d/%m/%Y')
    context[:sections]          = section_structs
    context[:kpis]              = grid_view_array
    context[:cap_table]         = cap_table

    # Add portco logo as a Sablon image if present
    logo_doc = @portco.documents.where(owner_tag: "logo").first
    add_image(context, :logo, logo_doc.file) if logo_doc&.file.present?

    # Include latest AI-extracted data for this portco if one exists
    latest_extract = @report.portfolio_report_extracts
                            .where(portfolio_company_id: @portco.id)
                            .order(created_at: :desc)
                            .first
    if latest_extract
      data       = JSON.parse(latest_extract.data)
      normalized = data.deep_transform_keys { |k| k.to_s.underscore.tr(' ', '_') }
      context[:report_data] = OpenStruct.new(normalized)
    end

    context[:context] = DocGenContext.new(context)
    context
  end

  def period_label
    "#{@start_date.strftime('%b %Y')} – #{@end_date.strftime('%b %Y')}"
  end

  # Builds one Section per draft section with pre-parsed bullets
  def section_structs
    ordered_sections.map do |section|
      html    = @draft.narrative_for(section.id).to_s
      bullets = extract_bullets(html)
      Section.new(name: section.name, narrative_html: html, bullets: bullets)
    end
  end

  def ordered_sections
    all = @report.portfolio_report_sections.index_by(&:id)
    @template.ordered_section_ids.filter_map { |id| all[id] }
  end

  # Strips HTML to plain bullet strings
  def extract_bullets(html)
    return [] if html.blank?

    doc     = Nokogiri::HTML.fragment(html)
    bullets = doc.css("li").map { |li| li.text.strip }.reject(&:empty?)
    bullets = doc.css("p").map  { |p|  p.text.strip  }.reject(&:empty?) if bullets.empty?
    bullets = html.split("\n").map(&:strip).reject(&:empty?) if bullets.empty?
    bullets
  end

  # Mirrors the KPI grid logic in PortfolioReportDocGenerator
  def grid_view_array
    kpi_reports = @portco.portfolio_kpi_reports
                         .includes(kpis: :investor_kpi_mapping)
                         .where(as_of: ..@end_date)
                         .order(:as_of)

    @portco.investor_kpi_mappings.where(show_in_report: true).map do |ikm|
      row = { "header" => ikm.standard_kpi_name }
      kpi_reports.each do |kr|
        kpi = kr.kpis.show_in_report.find { |k| k.name.casecmp?(ikm.standard_kpi_name) }
        row[kr.label] = kpi ? number_with_delimiter(kpi.value.round(2)) : "N/A"
      end
      OpenStruct.new(row)
    end
  end

  # Mirrors the cap_table helper in PortfolioReportDocGenerator
  def cap_table
    funding_rounds = @portco.investments
                            .where(investment_date: ..@end_date)
                            .order(investment_date: :asc)
                            .pluck(:funding_round).uniq

    result = GenerateCapTable.call(params: {
      funding_rounds:        funding_rounds,
      portfolio_company_id:  @portco.id,
      group_by_field:        :category
    })

    (result[:model] || []).map { |inv| OpenStruct.new(inv) }
  end
end

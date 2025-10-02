class PortfolioReportDocGenerator
  include CurrencyHelper
  include DocumentGeneratorBase

  attr_accessor :working_dir

  def initialize(portfolio_company, template, start_date, end_date, user_id, options: nil)
    Rails.logger.debug { "PortfolioCompanyDocGenerator #{portfolio_company.id}, #{template.name}, #{start_date}, #{end_date}, #{user_id}, #{options} " }

    portfolio_report_extract_id = options[:portfolio_report_extract_id]
    portfolio_report_extract = PortfolioReportExtract.find(portfolio_report_extract_id)

    create_working_dir(portfolio_company)
    template_path ||= download_template(template)
    generate(portfolio_company, portfolio_report_extract, template, template_path, start_date, end_date)
    generated_document_name = "#{template.name} #{portfolio_company.investor_name} #{start_date} to #{end_date}"

    # Folder to upload the generated document
    folder = Folder.find(options[:folder_id]) if options[:folder_id].present?
    folder ||= portfolio_company.document_folder.children.find_or_create_by(name: 'Portfolio Reports', entity_id: portfolio_company.entity_id)

    # Upload the generated document
    upload(template, portfolio_company, start_date, end_date, folder, generated_document_name, file_extension: 'docx', user_id: user_id)
  ensure
    cleanup
  end

  private

  def working_dir_path(portfolio_company)
    "tmp/portfolio_company/#{rand(1_000_000)}/#{portfolio_company.id}"
  end

  def download_template(template)
    file = template.file.download
    file.path
  end

  def generate(portfolio_company, portfolio_report_extract, _template_document, template_path, _start_date, end_date)
    template = Sablon.template(File.expand_path(template_path))

    # This is where the data extracted from the documents and notes is stored
    data = JSON.parse(portfolio_report_extract.data)
    # Convert keys to snake_case (or any other preferred format)
    normalized_hash = data.deep_transform_keys { |key| key.to_s.underscore.tr(' ', '_') }
    report_data = OpenStruct.new(normalized_hash)

    context = {}
    context.store  :portfolio_report_extract, portfolio_report_extract
    context.store  :report_data, report_data

    context.store :cap_table, cap_table(portfolio_company, end_date)
    context.store  :portfolio_company, TemplateDecorator.decorate(portfolio_company)
    context.store  :apis, TemplateDecorator.decorate_collection(portfolio_company.aggregate_portfolio_investments)
    context.store  :portfolio_investments, TemplateDecorator.decorate_collection(portfolio_company.portfolio_investments.where(investment_date: ..end_date))
    context.store  :kpis, grid_view_array(portfolio_company, end_date)

    current_date = Time.zone.now.strftime('%d/%m/%Y')
    context.store :current_date, current_date

    file_name = generated_file_name(portfolio_company)
    convert(template, context, file_name, to_pdf: false)
  end

  def cap_table(portfolio_company, end_date)
    funding_rounds = portfolio_company.investments.where(investment_date: ..end_date)
                                      .select(:funding_round, :investment_date)
                                      .order(investment_date: :asc)
                                      .pluck(:funding_round).uniq

    investments = Investment.generate_cap_table(funding_rounds, portfolio_company.id, group_by_field: :category)
    investments.map { |investment| OpenStruct.new(investment) }
  end

  include ActionView::Helpers::NumberHelper

  def grid_view_array(portfolio_company, end_date)
    kpi_reports = portfolio_company.portfolio_kpi_reports
                                   .where(as_of: ..end_date)
                                   .order(:as_of)

    investor_kpi_mappings = portfolio_company.investor_kpi_mappings

    rows = investor_kpi_mappings.map do |ikm|
      row_data = { "header" => ikm.standard_kpi_name }

      kpi_reports.each do |kr|
        kpi = kr.kpis.find { |k| k.name.casecmp?(ikm.standard_kpi_name) }

        row_data[kr.label] = kpi ? number_with_delimiter(kpi.value.round(2)) : "N/A"
      end

      OpenStruct.new(row_data)
    end

    Rails.logger.debug rows
    rows
  end
end

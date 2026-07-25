class PortfolioReportDocGenerator
  include CurrencyHelper
  include DocumentGeneratorBase

  attr_accessor :working_dir

  def initialize(portfolio_company, template, start_date, end_date, user_id, options: nil)
    @portfolio_company = portfolio_company
    @template = template
    @start_date = start_date
    @end_date = end_date
    @user_id = user_id
    @options = options
    call
  end

  def call
    Rails.logger.debug { "PortfolioCompanyDocGenerator #{@portfolio_company.id}, #{@template.name}, #{@start_date}, #{@end_date}, #{@user_id}, #{@options} " }

    portfolio_report_extract = PortfolioReportExtract.find(@options[:portfolio_report_extract_id])

    @template_name = @template.name
    # Download the template file - block keeps temp file available throughout
    @template.file.download do |tempfile|
      template_path = tempfile.path

      create_working_dir(@portfolio_company)
      generate(@portfolio_company, portfolio_report_extract, @template, template_path, @start_date, @end_date)
      generated_document_name = "#{@template.name} #{@portfolio_company.investor_name} #{@start_date} to #{@end_date}"

      # Folder to upload the generated document
      folder = Folder.find(@options[:folder_id]) if @options[:folder_id].present?
      folder ||= @portfolio_company.document_folder.children.find_or_create_by(name: 'Portfolio Reports', entity_id: @portfolio_company.entity_id)

      # Upload the generated document
      upload(@template, @portfolio_company, @start_date, @end_date, folder, generated_document_name, file_extension: 'docx', user_id: @user_id, as_of: @end_date&.to_date)
    ensure
      cleanup
    end
  end

  private

  def working_dir_path(portfolio_company)
    "tmp/portfolio_company/#{rand(1_000_000)}/#{portfolio_company.id}"
  end

  def generate(portfolio_company, portfolio_report_extract, _template_document, template_path, start_date, end_date)
    template = Sablon.template(File.expand_path(template_path))

    # This is where the data extracted from the documents and notes is stored. The extract can be
    # empty (no documents, or "generate missing extracts" was off). The template iterates over each
    # section's value, so a missing/nil value would blow up ("expecting enumerable"). Instead we
    # build a hash keyed by every configured section name with a single "No data available" point,
    # so each section renders that placeholder uniformly — no separate no_data branch in the template.
    normalized_hash =
      if portfolio_report_extract.data.present?
        # Convert keys to snake_case (or any other preferred format)
        JSON.parse(portfolio_report_extract.data)
            .deep_transform_keys { |key| key.to_s.underscore.tr(' ', '_') }
      else
        portfolio_report_extract.portfolio_report.portfolio_report_sections.pluck(:name)
                                .to_h { |name| [name.to_s.underscore.tr(' ', '_'), ["No data available"]] }
      end
    report_data = OpenStruct.new(normalized_hash)

    context = {}
    context.store  :portfolio_report_extract, portfolio_report_extract
    context.store  :report_data, report_data

    # When the user opted in, expose the extract's source documents so the template can render them
    # as an audits section (loop `audits`; image-type docs embed via the same add_image path).
    audits = portfolio_report_extract.source_documents.pluck(:name).map do |doc_name|
      OpenStruct.new(name: doc_name)
    end
    context.store :audits, TemplateDecorator.decorate_collection(audits)

    add_fund_level_data(context, portfolio_company, start_date, end_date)

    context.store :cap_table, cap_table(portfolio_company, end_date)
    context.store  :portfolio_company, TemplateDecorator.decorate(portfolio_company)
    context.store  :apis, TemplateDecorator.decorate_collection(portfolio_company.aggregate_portfolio_investments)
    context.store  :portfolio_investments, TemplateDecorator.decorate_collection(portfolio_company.portfolio_investments.where(investment_date: ..end_date))

    logo_doc = portfolio_company.documents.where(owner_tag: "logo").first
    add_image(context, :logo, logo_doc.file) if logo_doc&.file.present?

    context.store :kpis, TemplateDecorator.decorate_collection(grid_view_array(portfolio_company, end_date))

    portfolio_company.investor_kpi_mappings.pluck(:category).uniq.each_with_index do |category, _index|
      context.store :"#{category.to_s.gsub(/\s+/, '_').underscore}_kpis", TemplateDecorator.decorate_collection(grid_view_array(portfolio_company, end_date, category: category))
    end

    current_date = Time.zone.now.strftime('%d/%m/%Y')
    context.store :current_date, current_date
    # This is only for dumping keys for debugging inside the template
    context.store :context, DocGenContext.new(context)

    file_name = generated_file_name(portfolio_company)
    convert(template, context, file_name, to_pdf: false, template_name: @template_name)
  end

  def cap_table(portfolio_company, end_date)
    funding_rounds = portfolio_company.investments.where(investment_date: ..end_date)
                                      .select(:funding_round, :investment_date)
                                      .order(investment_date: :asc)
                                      .pluck(:funding_round).uniq

    result = GenerateCapTable.call(params: {
                                     funding_rounds: funding_rounds,
                                     portfolio_company_id: portfolio_company.id,
                                     group_by_field: :category
                                   })

    # Ensure we always return an array (result[:model] might be nil)
    model_data = result[:model] || []
    model_data.map { |investment| OpenStruct.new(investment) }
  end

  include ActionView::Helpers::NumberHelper

  def grid_view_array(portfolio_company, end_date, category: nil)
    kpi_reports = portfolio_company.portfolio_kpi_reports
                                   .includes(kpis: :investor_kpi_mapping)
                                   .where(as_of: ..end_date)
                                   .order(:as_of)

    investor_kpi_mappings = portfolio_company.investor_kpi_mappings.where(show_in_report: true)
    investor_kpi_mappings = investor_kpi_mappings.where(category: category) if category.present?

    rows = investor_kpi_mappings.map do |ikm|
      row_data = { "header" => ikm.standard_kpi_name }

      kpi_reports.each do |kr|
        kpi = kr.kpis.show_in_report.find { |k| k.name.casecmp?(ikm.standard_kpi_name) }
        # Underscored labels so template merge fields are predictable ("q1_fy25", not "Q1 FY25"),
        # and the value is stored RAW (previously rounded + delimited here) so the template /
        # TemplateDecorator decides formatting — pre-formatting broke templates that needed the
        # number for further math. Each period also gets a "<label>_percent" companion so the
        # template can show the KPI's change alongside its value.
        label = kr.label.underscore
        percentage_label = "#{label}_percent"
        row_data[label] = kpi ? kpi.value : "N/A"
        row_data[percentage_label] = kpi ? kpi.percentage_change : "N/A"
      end

      OpenStruct.new(row_data)
    end

    Rails.logger.debug rows
    rows
  end

  def add_fund_level_data(context, portfolio_company, _start_date, end_date)
    company_portfolio_investments = portfolio_company.portfolio_investments.where(investment_date: ..end_date).includes(:fund)
    fund_ids = company_portfolio_investments.pluck(:fund_id).uniq
    funds = Fund.where(id: fund_ids)

    funds.each do |fund|
      # as_of recomputes and FREEZES each PI, returning a plain Array — so fmv/cost/latest below
      # must use Enumerable methods, not AR relation methods (.buys/.order/SQL-string sum).
      fund_pis = company_portfolio_investments.where(fund_id: fund.id).map { |pi| pi.as_of(end_date) }
      buys = fund_pis.select { |pi| pi.quantity.to_f.positive? }
      struct = OpenStruct.new(
        name: fund.name,
        currency: fund.currency,
        # with pis as_of, we can use sum &:
        fmv: Money.new(fund_pis.sum(&:fmv_cents), fund.currency),
        cost_of_investment: Money.new(buys.sum(&:amount_cents), fund.currency)
      )

      context.store :"#{fund.name.parameterize.underscore}_data", TemplateDecorator.decorate(struct)

      # add latest PI
      latest_pi = fund_pis.max_by(&:investment_date)
      context.store :"#{fund.name.parameterize.underscore}_latest_pi", TemplateDecorator.decorate(latest_pi)
    end
  end
end

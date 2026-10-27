class PortfolioReportDocGenerator
  include CurrencyHelper
  include DocumentGeneratorBase

  attr_accessor :working_dir

  # Tags an Actual column is compared with. Each adds a "<label>_vs_<tag>_percent" field (Actual as a % of the tag) and a
  # "<label>_vs_<tag>_compute_percent" field (Actual's % difference from the tag); adding "IC" here gives
  # "<label>_vs_ic_percent" and "<label>_vs_ic_compute_percent" with no other change.
  COMPARATOR_TAGS = ["Budget"].freeze

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

  def generate(portfolio_company, portfolio_report_extract, template_document, template_path, start_date, end_date)
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
    context.store :portfolio_report_extract, portfolio_report_extract
    context.store :report_data, report_data

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
    # doc_template is inert here: to_pdf: false means convert_to_accessible_pdf (the only
    # consumer of doc_template) never runs for this generator, which only ever produces a
    # .docx. Threaded through anyway for consistency with every other doc generator.
    convert(template, context, file_name, to_pdf: false, template_name: @template_name, doc_template: template_document)
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
                                   .to_a

    investor_kpi_mappings = portfolio_company.investor_kpi_mappings.where(show_in_report: true)
    investor_kpi_mappings = investor_kpi_mappings.where(category: category) if category.present?

    # Built once, so no query runs per mapping per report. Approved KPIs only: an unapproved one reads as missing.
    kpis_by_report = kpi_reports.to_h { |kr| [kr.id, kr.report_kpis_by_name] }
    reports_by_key = kpi_reports.index_by { |kr| comparator_key(kr.period, kr.as_of, kr.tag_list) }

    rows = investor_kpi_mappings.map do |ikm|
      # data_type ("money", "numeric", "percentage") lets the template format the row; percentages are stored as fractions (0.12)
      # category lets the template group or label rows; kept as saved (a display name), blank when the mapping has none.
      # H1, H2 the mapping's category on the row, in the all-KPIs list and in its own category's list; H3 other fields unchanged;
      # E1 case kept; E2 no category gives ""
      row_data = { "header" => ikm.standard_kpi_name, "data_type" => ikm.data_type.to_s.downcase, "category" => ikm.category.to_s }
      name = ikm.standard_kpi_name.downcase

      kpi_reports.each do |kr|
        kpi = kpis_by_report.dig(kr.id, name)
        # Underscored labels so template merge fields are predictable ("q1_fy25", not "Q1 FY25"),
        # and the value is stored RAW (previously rounded + delimited here) so the template /
        # TemplateDecorator decides formatting — pre-formatting broke templates that needed the
        # number for further math. Each period also gets a "<label>_percent" companion so the
        # template can show the KPI's change alongside its value.
        label = kr.label.underscore
        percentage_label = "#{label}_percent"
        row_data[label] = kpi ? kpi.value : "N/A"
        row_data[percentage_label] = kpi ? kpi.percentage_change : "N/A"

        # Computed here, not stored: a Budget approved after the Actual shows on the next generation (E22)
        next unless kr.tag_list.to_s.casecmp?("Actual")

        COMPARATOR_TAGS.each do |tag|
          comparator_report = reports_by_key[comparator_key(kr.period, kr.as_of, tag)]
          comparator_kpi = kpis_by_report.dig(comparator_report&.id, name)
          row_data["#{label}_vs_#{tag.downcase}_percent"] = percent_of(kpi, comparator_kpi)
          row_data["#{label}_vs_#{tag.downcase}_compute_percent"] = variance_of(kpi, comparator_kpi)
        end
      end

      OpenStruct.new(row_data)
    end

    Rails.logger.debug rows
    rows
  end

  # Period and tag are free text, so they are matched without regard to case, as the Actual check above is
  def comparator_key(period, as_of, tag)
    [period.to_s.downcase, as_of, tag.to_s.downcase]
  end

  # Actual as a percentage of the comparator (92 means 92%); "N/A" when either figure is missing or the comparator is zero
  def percent_of(kpi, comparator)
    return "N/A" if kpi.nil? || comparator.nil? || comparator.value.zero?

    kpi.value / comparator.value * 100
  end

  # How far Actual is from the comparator, as a percentage of the comparator (-8 means 8% below); "N/A" when either
  # figure is missing or the comparator is zero. H16, H17, E25, E26
  def variance_of(kpi, comparator)
    return "N/A" if kpi.nil? || comparator.nil? || comparator.value.zero?

    (kpi.value - comparator.value) / comparator.value * 100
  end

  def add_fund_level_data(context, portfolio_company, _start_date, end_date)
    company_portfolio_investments = portfolio_company.portfolio_investments.where(investment_date: ..end_date).includes(:fund)
    fund_ids = company_portfolio_investments.pluck(:fund_id).uniq
    funds = Fund.where(id: fund_ids)
    ratios = fund_ratio_values(portfolio_company, fund_ids, end_date)

    add_investment_milestones(context, company_portfolio_investments)

    funds.each do |fund|
      # as_of recomputes and FREEZES each PI, returning a plain Array — so fmv/cost/latest below
      # must use Enumerable methods, not AR relation methods (.buys/.order/SQL-string sum).
      fund_pis = PortfolioInvestmentsAsOf.call(company_portfolio_investments.where(fund_id: fund.id), end_date.to_date)
      buys = fund_pis.select { |pi| pi.quantity.to_f.positive? }
      sells = fund_pis.select { |pi| pi.quantity.to_f.negative? }
      struct = OpenStruct.new(
        name: fund.name,
        currency: fund.currency,
        # with pis as_of, we can use sum &:
        fmv: Money.new(fund_pis.sum(&:fmv_cents), fund.currency),
        cost_of_investment: Money.new(buys.sum(&:amount_cents), fund.currency),
        # the cost of what is still held at the end date, net of what was sold. H15
        cost_of_remaining: Money.new(fund_pis.sum(&:cost_of_remaining_cents), fund.currency),
        # what the fund received from the sales up to the end date: the sells' own amounts, positive. H14, E23
        sold_amount: Money.new(sells.sum(&:amount_cents), fund.currency),
        irr: ratios.fetch([fund.id, "IRR"], "N/A"),
        moic: ratios.fetch([fund.id, "MOIC"], "N/A")
      )

      context.store :"#{fund.name.parameterize.underscore}_data", TemplateDecorator.decorate(struct)

      # add latest PI
      latest_pi = fund_pis.max_by(&:investment_date)
      context.store :"#{fund.name.parameterize.underscore}_latest_pi", TemplateDecorator.decorate(latest_pi)
    end
  end

  # The company's IRR (XIRR) and MOIC in each fund, as the fund ratio runs stored them: the latest run on or before
  # end_date, Default scenario, fund currency. Keyed [fund_id, "IRR" | "MOIC"]; a ratio that was never run is absent.
  def fund_ratio_values(portfolio_company, fund_ids, end_date)
    FundRatio.default
             .where(owner_type: "Investor", owner_id: portfolio_company.id, fund_id: fund_ids, name: %w[IRR MOIC],
                    computation_context_id: nil, end_date: ..end_date)
             .order(end_date: :desc, id: :desc)
             .pluck(:fund_id, :name, :value)
             .each_with_object({}) { |(fund_id, name, value), latest| latest[[fund_id, name]] ||= value }
  end

  # Across all the company's funds: the template reads the stake custom field off the latest investment, buy or
  # sale (latest_pi.custom_fields.stake), and the first investment date off the earliest buy
  # (earliest_pi.investment_date). With no investment yet both are blank, so a template that reads
  # them still renders.
  def add_investment_milestones(context, portfolio_investments)
    latest = portfolio_investments.reorder(investment_date: :desc, id: :desc).first
    earliest = portfolio_investments.buys.reorder(investment_date: :asc, id: :asc).first

    { latest_pi: latest, earliest_pi: earliest }.each do |key, pi|
      context.store key, TemplateDecorator.decorate(pi || OpenStruct.new(investment_date: nil, custom_fields: OpenStruct.new))
    end
  end
end

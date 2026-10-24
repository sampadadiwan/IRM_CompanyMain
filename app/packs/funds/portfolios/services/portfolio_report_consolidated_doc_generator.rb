# Renders one .docx from a template for ALL the given portfolio companies at once, for consolidated
# portfolio reports (cover, summary, disclaimer pages). The template reads `portfolio_companies`, a list
# with one entry per company holding portfolio_company, latest_pi, earliest_pi, funds (name, currency, fmv,
# cost_of_investment, irr, moic per fund) and logo, plus `fund_totals` (per fund: name, currency, fmv, cost_of_investment and
# the sum of each numeric company custom field across the companies in that fund) and `current_date`.
#
# It makes no PortfolioReportExtract, never calls the language model and saves no Document: the caller
# (PortfolioReportJob) joins the returned file into the combined document.
class PortfolioReportConsolidatedDocGenerator
  include CurrencyHelper
  include DocumentGeneratorBase

  # @param portfolio_companies [Enumerable<Investor>]
  # @param template [Document] The report template.
  # @param start_date [Date]
  # @param end_date [Date]
  # @param user_id [Integer]
  # @param output_dir [String] Existing folder the .docx (and any logo copies) is written into; the caller removes it.
  def initialize(portfolio_companies, template, start_date, end_date, user_id, output_dir:)
    @portfolio_companies = portfolio_companies
    @template = template
    @start_date = start_date
    @end_date = end_date
    @user_id = user_id
    @working_dir = output_dir
  end

  # @return [String] Path of the rendered .docx.
  def call
    Rails.logger.debug { "PortfolioReportConsolidatedDocGenerator #{@template.name}, #{@portfolio_companies.size} companies, #{@start_date}, #{@end_date}, #{@user_id}" }

    # H2, H3: the template is rendered once, for every company
    @template.file.download do |tempfile|
      template = Sablon.template(File.expand_path(tempfile.path))
      file_name = "#{@working_dir}/consolidated-#{@template.id}"

      # H3, E4: companies A-Z, each with its own fresh hash so keys (logo, fund data) never leak between companies
      companies = @portfolio_companies.sort_by { |company| company.investor_name.to_s.downcase }
      company_hashes = companies.map { |company| company_data(company) }
      context = {
        portfolio_companies: company_hashes,
        fund_totals: fund_totals(company_hashes),
        current_date: Time.zone.now.strftime('%d/%m/%Y')
      }

      # Only a .docx is produced (to_pdf: false), so doc_template, used for PDF accessibility, is not needed
      convert(template, context, file_name, to_pdf: false, template_name: @template.name, doc_template: @template)
      File.expand_path("#{file_name}.docx")
    end
  end

  private

  # One company's own hash: the company, its latest and earliest investment, its IRR and MOIC in each fund
  # and the logo. Deliberately far smaller than a normal report's data (no KPIs, cap table or fund-named keys).
  def company_data(portfolio_company)
    investments = portfolio_company.portfolio_investments.where(investment_date: ..@end_date)
    fund_ids = investments.pluck(:fund_id).uniq
    ratios = fund_ratio_values(portfolio_company, fund_ids)

    # latest is any investment, buy or sale; earliest is the first buy. Blank when there is none, so the template still renders
    latest = investments.reorder(investment_date: :desc, id: :desc).first
    earliest = investments.buys.reorder(investment_date: :asc, id: :asc).first
    blank = -> { OpenStruct.new(investment_date: nil, custom_fields: OpenStruct.new) }

    context = {
      portfolio_company: TemplateDecorator.decorate(portfolio_company),
      latest_pi: TemplateDecorator.decorate(latest || blank.call),
      earliest_pi: TemplateDecorator.decorate(earliest || blank.call)
    }
    add_funds(context, investments, fund_ids, ratios)

    logo_doc = portfolio_company.documents.where(owner_tag: "logo").first
    add_image(context, :logo, logo_doc.file) if logo_doc&.file.present?
    context
  end

  # The funds as a list, so a template loops them ({{#funds}}{{name}} {{irr}} {{moic}}{{/funds}}) without knowing their
  # names. Each fund also has `ratios`, a list of name/value rows ({{#ratios}}{{name}} {{value}}{{/ratios}}), for a
  # third loop: companies, then funds, then ratios.
  def add_funds(context, investments, fund_ids, ratios)
    summaries = Fund.where(id: fund_ids).map do |fund|
      # as_of recomputes and freezes each investment and returns a plain Array, so sum with Enumerable methods
      fund_pis = investments.where(fund_id: fund.id).map { |pi| pi.as_of(@end_date) }
      buys = fund_pis.select { |pi| pi.quantity.to_f.positive? }
      irr = ratios.fetch([fund.id, "IRR"], "N/A")
      moic = ratios.fetch([fund.id, "MOIC"], "N/A")
      OpenStruct.new(
        id: fund.id,
        name: fund.name,
        currency: fund.currency,
        fmv: Money.new(fund_pis.sum(&:fmv_cents), fund.currency),
        cost_of_investment: Money.new(buys.sum(&:amount_cents), fund.currency),
        irr: irr,
        moic: moic,
        ratios: [OpenStruct.new(name: "IRR", value: irr), OpenStruct.new(name: "MOIC", value: moic)]
      )
    end

    context[:funds] = TemplateDecorator.decorate_collection(summaries)
  end

  # One entry per fund the companies invested in, summed over the companies in that fund: fmv, cost_of_investment and
  # custom_fields, the total of each numeric company custom field. Built once from the finished company hashes so
  # nothing is added to a company's own data. H15, E20
  def fund_totals(company_hashes)
    lines = company_hashes.flat_map do |hash|
      hash[:funds].map { |fund| [hash[:portfolio_company].object, fund.object] }
    end
    field_names = numeric_custom_field_names(company_hashes.map { |hash| hash[:portfolio_company].object })

    totals = lines.group_by { |_, fund| fund.id }.values.map do |fund_lines|
      funds = fund_lines.map(&:last)
      currency = funds.first.currency
      OpenStruct.new(
        name: funds.first.name,
        currency: currency,
        fmv: Money.new(funds.sum { |fund| fund.fmv.cents }, currency),
        cost_of_investment: Money.new(funds.sum { |fund| fund.cost_of_investment.cents }, currency),
        custom_fields: custom_field_sums(fund_lines.map(&:first), field_names)
      )
    end
    TemplateDecorator.decorate_collection(totals)
  end

  # Names of the number and money custom fields in the companies' form types (normally a single form type).
  def numeric_custom_field_names(companies)
    companies.filter_map(&:form_type).uniq
             .flat_map { |form_type| form_type.form_custom_fields.visible.where(field_type: %w[NumberField Money]).pluck(:name) }
             .uniq
  end

  # name => sum of that field's stored value over the companies; a blank counts as zero. E21
  def custom_field_sums(companies, field_names)
    sums = field_names.index_with { |name| companies.sum(0.to_d) { |company| company.custom_fields[name].to_d } }
    OpenStruct.new(sums)
  end

  # The company's IRR and MOIC in each fund, as the fund ratio runs stored them: the latest run on or before the
  # end date, Default scenario. Keyed [fund_id, "IRR" | "MOIC"]; a ratio that was never run is absent.
  def fund_ratio_values(portfolio_company, fund_ids)
    FundRatio.default
             .where(owner_type: "Investor", owner_id: portfolio_company.id, fund_id: fund_ids, name: %w[IRR MOIC],
                    computation_context_id: nil, end_date: ..@end_date)
             .order(end_date: :desc, id: :desc)
             .pluck(:fund_id, :name, :value)
             .each_with_object({}) { |(fund_id, name, value), latest| latest[[fund_id, name]] ||= value }
  end
end

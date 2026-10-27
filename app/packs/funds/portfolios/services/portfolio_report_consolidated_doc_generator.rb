# Renders one .docx from a template for ALL the given portfolio companies at once, for consolidated
# portfolio reports (cover, summary, disclaimer pages). The template reads `portfolio_companies`, a list
# with one entry per company holding portfolio_company, latest_pi, earliest_pi, funds and logo, plus `fund_totals`
# and `current_date`. Each of the company's funds (a FundLine) holds: the fund's money as of the end date (committed, call,
# collected, distribution, target committed, units premium and the tracking-currency ones); cost_of_investment (all
# purchases to the end date, prior to the start date, and between the dates), cost_of_remaining (cost of what is still held
# at the end date and the day before the start), cost_of_sold_between (positive); fmv at the end date, the day before the
# start (fmv_prior) and the day before the financial year (fmv_fy_start) with the % change from each; the company's
# own irr and moic; and the fund's own gross_portfolio_irr. `fund_totals` has one entry per fund, summed over the companies in it; its returns (irr, gross_portfolio_irr,
# moic, tvpi, dpi, rvpi) are the fund's own stored ratios, taken once.
#
# It makes no PortfolioReportExtract, never calls the language model and saves no Document: the caller
# (PortfolioReportJob) joins the returned file into the combined document.
class PortfolioReportConsolidatedDocGenerator
  include CurrencyHelper
  include DocumentGeneratorBase

  # Fixed-shape values for the template: a missing key fails when built instead of rendering blank. The % fields are
  # numbers times 100 (the template adds the % sign), or "N/A" when the figure they divide by is zero.
  Ratio = Data.define(:name, :value)
  FundLine = Data.define(
    :id, :name, :currency,
    :committed_amount, :call_amount, :collected_amount, :distribution_amount, :target_committed_amount, :total_units_premium,
    :tracking_committed_amount, :tracking_call_amount, :tracking_collected_amount, :tracking_distribution_amount,
    :cost_of_investment, :cost_of_investment_prior, :cost_of_investment_between,
    :cost_of_remaining, :cost_of_remaining_prior, :cost_of_sold_between,
    :fmv, :fmv_prior, :fmv_change_percent, :fmv_fy_start, :fmv_fy_start_change_percent,
    :fmv_at_prior_quantity, :fmv_at_fy_start_quantity,
    :irr, :gross_portfolio_irr, :moic, :ratios
  )
  # One per fund. Money is the fund's own (taken once, never added up over the companies); cost and fmv are added up
  # over the companies; the returns are the fund's own stored ratios, not the companies'. custom_fields stays an
  # OpenStruct as its keys are the companies' form field names.
  FundTotal = Data.define(
    :name, :currency,
    :committed_amount, :call_amount, :collected_amount, :distribution_amount, :target_committed_amount, :total_units_premium,
    :tracking_committed_amount, :tracking_call_amount, :tracking_collected_amount, :tracking_distribution_amount,
    :collected_percent, :uncollected_amount, :uncollected_percent, :company_count,
    :cost_of_investment, :cost_of_investment_prior, :cost_of_investment_between,
    :cost_of_remaining, :cost_of_remaining_prior, :cost_of_sold_between,
    :fmv, :fmv_prior, :fmv_change_percent, :fmv_at_prior_quantity,
    :irr, :gross_portfolio_irr, :moic, :tvpi, :dpi, :rvpi, :custom_fields
  )
  # The fund's own ratio behind each return; the fund's IRR is stored as its XIRR. gross_portfolio_irr is the return on the
  # portfolio investments before fund fees and expenses, read by its plain name only (not a label or the tracking currency one).
  # It is the fund's, so a company's fund line shows the same value as the fund total, beside the company's own irr. H4-H7, E3-E11
  FUND_RETURN_RATIOS = { irr: "XIRR", gross_portfolio_irr: "Gross Portfolio IRR", moic: "MOIC", tvpi: "TVPI", dpi: "DPI", rvpi: "RVPI" }.freeze
  FUND_LINE_MONEY = %i[committed_amount call_amount collected_amount distribution_amount target_committed_amount total_units_premium
                       tracking_committed_amount tracking_call_amount tracking_collected_amount tracking_distribution_amount].freeze
  FUND_LINE_SUMS = %i[cost_of_investment cost_of_investment_prior cost_of_investment_between cost_of_remaining
                      cost_of_remaining_prior cost_of_sold_between fmv fmv_prior fmv_at_prior_quantity].freeze

  # @param portfolio_companies [Enumerable<Investor>]
  # @param template [Document] The report template.
  # @param start_date [Date]
  # @param end_date [Date]
  # @param user_id [Integer]
  # @param output_dir [String] Existing folder the .docx (and any logo copies) is written into; the caller removes it.
  def initialize(portfolio_companies, template, start_date, end_date, user_id, output_dir:)
    @portfolio_companies = portfolio_companies
    @template = template
    @start_date = to_date(start_date, "start date")
    @end_date = to_date(end_date, "end date")
    @user_id = user_id
    @working_dir = output_dir
    @financial_year_days = {}
    @fund_as_ofs = {}
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
      end_date_val = Time.zone.parse(@end_date.to_s)
      context = {
        end_date: end_date_val.strftime('%d/%m/%Y'),
        date_format_end_date: I18n.l(end_date_val, format: :day_month_year),
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

  # The job hands the dates over as text, and the figures below need real dates (the day before the start). X2
  def to_date(value, name)
    parsed = Time.zone.parse(value.to_s)
    raise ArgumentError, "#{name} is required" unless parsed

    parsed.to_date
  end

  # The last day before the period: the date the "prior" cost and value are worked out as of. H1
  def prior_day
    @start_date.yesterday
  end

  # The last day of the financial year before the one the end date is in (31 March for an April year): the date
  # fmv_fy_start is worked out as of. Same year-start rule as the KPI reports: the fund's own setting, then the
  # entity's, then the country default. Per fund, as a fund can set its own. H2, E3, E4
  def financial_year_day(fund)
    @financial_year_days[fund.id] ||= begin
      start_month = KpiDateUtils.resolve_fiscal_year_start_month(fund, fund.entity_id)
      KpiDateUtils.fiscal_year_start(@end_date, start_month).yesterday
    end
  end

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
    lines = Fund.where(id: fund_ids).map { |fund| fund_line(fund, investments.where(fund_id: fund.id), ratios) }
    context[:funds] = TemplateDecorator.decorate_collection(lines)
  end

  # One company in one fund. The company's investments in the fund are valued as of the end date, the day before the
  # start and the day before the financial year (X1: each date loads its own records). The purchases and sales in the
  # period come from the end-date set, split on their own date, so they need no pass of their own.
  # Money is Money in the fund's currency. H3-H8, E1-E14
  def fund_line(fund, fund_investments, ratios)
    end_pis = PortfolioInvestmentsAsOf.call(fund_investments, @end_date)
    prior_pis = PortfolioInvestmentsAsOf.call(fund_investments.where(investment_date: ...@start_date), prior_day)
    fy_day = financial_year_day(fund)
    # a quarter that starts on the financial year start has the same day for both, so it is valued once
    fy_pis = fy_day == prior_day ? prior_pis : PortfolioInvestmentsAsOf.call(fund_investments.where(investment_date: ..fy_day), fy_day)

    # as_of freezes each investment and returns a plain Array, so sum with Enumerable methods
    buys = end_pis.select { |pi| pi.quantity.to_f.positive? }
    prior_buys, period_buys = buys.partition { |pi| pi.investment_date < @start_date }
    period_sells = end_pis.select { |pi| pi.quantity.to_f.negative? && pi.investment_date >= @start_date }
    money = ->(cents) { Money.new(cents, fund.currency) }
    fmv = end_pis.sum(&:fmv_cents)
    fmv_prior = prior_pis.sum(&:fmv_cents)
    fmv_fy_start = fy_pis.sum(&:fmv_cents)
    # the holdings at each earlier date, valued at the end date's value per unit: the change in value per unit, whatever was
    # bought or sold since. H19-H24, E25-E32
    unit_values = unit_values_at_end(prior_pis + fy_pis, fund)
    fmv_at_prior_quantity = value_at_unit_values(prior_pis, unit_values)
    fmv_at_fy_start_quantity = value_at_unit_values(fy_pis, unit_values)
    fund_as_of = (@fund_as_ofs[fund.id] ||= fund.as_of(@end_date))
    irr = ratios.fetch([fund.id, "IRR"], "N/A")
    moic = ratios.fetch([fund.id, "MOIC"], "N/A")

    FundLine.new(
      id: fund.id, name: fund.name, currency: fund.currency,
      committed_amount: fund_as_of.committed_amount, call_amount: fund_as_of.call_amount,
      collected_amount: fund_as_of.collected_amount, distribution_amount: fund_as_of.distribution_amount,
      target_committed_amount: fund_as_of.target_committed_amount, total_units_premium: fund_as_of.total_units_premium,
      tracking_committed_amount: fund_as_of.tracking_committed_amount, tracking_call_amount: fund_as_of.tracking_call_amount,
      tracking_collected_amount: fund_as_of.tracking_collected_amount, tracking_distribution_amount: fund_as_of.tracking_distribution_amount,
      cost_of_investment: money.call(buys.sum(&:amount_cents)),
      cost_of_investment_prior: money.call(prior_buys.sum(&:amount_cents)),
      cost_of_investment_between: money.call(period_buys.sum(&:amount_cents)),
      cost_of_remaining: money.call(end_pis.sum(&:cost_of_remaining_cents)),
      cost_of_remaining_prior: money.call(prior_pis.sum(&:cost_of_remaining_cents)),
      # stored negative on a sale; shown as a positive exit. H5
      cost_of_sold_between: money.call(period_sells.sum { |pi| pi.cost_of_sold_cents.abs }),
      fmv: money.call(fmv), fmv_prior: money.call(fmv_prior), fmv_change_percent: change_percent(fmv_at_prior_quantity, fmv_prior),
      fmv_fy_start: money.call(fmv_fy_start), fmv_fy_start_change_percent: change_percent(fmv_at_fy_start_quantity, fmv_fy_start),
      fmv_at_prior_quantity: money.call(fmv_at_prior_quantity), fmv_at_fy_start_quantity: money.call(fmv_at_fy_start_quantity),
      irr:, moic:, ratios: [Ratio.new(name: "IRR", value: irr), Ratio.new(name: "MOIC", value: moic)],
      # the fund's own, the same on every company's line in the fund. H7
      gross_portfolio_irr: fund_returns.fetch([fund.id, FUND_RETURN_RATIOS[:gross_portfolio_irr]], "N/A")
    )
  end

  # The value per unit of each instrument held in the list, at the end date, in the fund's currency: the latest valuation on or
  # before it, looked up once per instrument and not once per investment. 0 when there is none. Keyed by instrument id.
  def unit_values_at_end(pis, fund)
    pis.select(&:buy?).uniq(&:investment_instrument_id).to_h do |pi|
      [pi.investment_instrument_id, pi.latest_valuation_on(@end_date)&.per_share_value_in(fund.currency, @end_date, fund:) || 0]
    end
  end

  # What the buys in the list were holding at the date the list was valued for (net_quantity), worth at the given value per
  # unit, in cents. Sales carry no value of their own, so only buys count.
  def value_at_unit_values(pis, unit_values)
    pis.select(&:buy?).sum { |pi| pi.net_quantity * unit_values.fetch(pi.investment_instrument_id, 0) }.round
  end

  # (current - base) / the size of base * 100, so a negative base does not reverse the sign, or "N/A" when there is no base
  # to compare with. E12, E13, H17, E20, E21
  def change_percent(current, base)
    return "N/A" if base.to_d.zero?

    (current.to_d - base.to_d) / base.to_d.abs * 100
  end

  # One entry per fund the companies invested in (a FundTotal): the fund's money, the cost and fmv figures added up over the
  # companies in that fund, the % changes and collection % worked out from those, the number of companies, the fund's own
  # returns, and custom_fields, the total of each numeric company custom field. Built once from the finished company hashes
  # so nothing is added to a company's own data. H9-H13, E15-E22, H15, E20
  def fund_totals(company_hashes)
    lines = company_hashes.flat_map do |hash|
      hash[:funds].map { |fund| [hash[:portfolio_company].object, fund.object] }
    end
    field_names = numeric_custom_field_names(company_hashes.map { |hash| hash[:portfolio_company].object })
    returns = fund_returns

    totals = lines.group_by { |_, fund| fund.id }.values.map do |fund_lines|
      funds = fund_lines.map(&:last)
      fund_total(funds, returns, custom_field_sums(fund_lines.map(&:first), field_names))
    end
    TemplateDecorator.decorate_collection(totals)
  end

  # funds are one fund's lines, one per company. The money is the same on each line, so the first is taken (E15).
  def fund_total(funds, returns, custom_fields)
    first = funds.first
    currency = first.currency
    sums = FUND_LINE_SUMS.index_with { |field| Money.new(funds.sum { |line| line.public_send(field).cents }, currency) }
    money = FUND_LINE_MONEY.index_with { |field| first.public_send(field) }
    uncollected = money[:committed_amount] - money[:collected_amount]

    FundTotal.new(
      name: first.name, currency:, **money, **sums,
      collected_percent: part_percent(money[:collected_amount], money[:committed_amount]),
      uncollected_amount: uncollected,
      uncollected_percent: part_percent(uncollected, money[:committed_amount]),
      company_count: funds.size,
      # worked from the sums, as the fund's value per unit changes by instrument, not by company. H22
      fmv_change_percent: change_percent(sums[:fmv_at_prior_quantity].cents, sums[:fmv_prior].cents),
      **FUND_RETURN_RATIOS.keys.index_with { |key| returns.fetch([first.id, FUND_RETURN_RATIOS[key]], "N/A") },
      custom_fields:
    )
  end

  # part as a % of whole, or "N/A" when the whole is zero. H9, E16
  def part_percent(part, whole)
    return "N/A" if whole.cents.zero?

    part.cents.to_d / whole.cents * 100
  end

  # The funds' own returns as the fund ratio runs stored them: the latest Default-scenario run on or before the end date.
  # Keyed [fund_id, ratio name]; a ratio that was never run is absent. One query for the funds of all the companies,
  # loaded on first use and shared by the fund lines and the fund totals. H12, H13, E20-E22
  def fund_returns
    @fund_returns ||= FundRatio.default
                               .where(owner_type: "Fund", owner_id: report_fund_ids, name: FUND_RETURN_RATIOS.values, computation_context_id: nil,
                                      end_date: ..@end_date, entity_id: @portfolio_companies.map(&:entity_id).uniq)
                               .order(end_date: :desc, id: :desc)
                               .pluck(:owner_id, :name, :value)
                               .each_with_object({}) { |(fund_id, name, value), latest| latest[[fund_id, name]] ||= value }
  end

  # The funds any of the companies invested in on or before the end date: the funds that get a line and a total
  def report_fund_ids
    PortfolioInvestment.where(portfolio_company_id: @portfolio_companies.map(&:id), investment_date: ..@end_date).distinct.pluck(:fund_id)
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

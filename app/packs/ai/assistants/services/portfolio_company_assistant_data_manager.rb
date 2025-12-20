# PortfolioCompanyAssistantDataManager
#
# Handles business logic and data retrieval for the PortfolioCompanyAssistant.
# Focused on portfolio company specific data: valuations, investments, KPIs, and documents.
#
class PortfolioCompanyAssistantDataManager
  # Query object for filtering Valuations.
  class ValuationQuery
    include HasScope

    # Add scopes if needed
    def perform(collection:, params:)
      apply_scopes(collection, params)
    end
  end

  # Query object for filtering PortfolioInvestments.
  class PortfolioInvestmentQuery
    include HasScope

    has_scope :buys, type: :boolean
    has_scope :sells, type: :boolean
    has_scope :conversions, type: :boolean
    has_scope :distributed, type: :boolean
    has_scope :not_distributed, type: :boolean
    has_scope :proforma, type: :boolean
    has_scope :non_proforma, type: :boolean

    def perform(collection:, params:)
      apply_scopes(collection, params)
    end
  end

  # Query object for filtering KPIs.
  class KpiQuery
    include HasScope

    has_scope :actuals, type: :boolean
    has_scope :budgets, type: :boolean
    has_scope :ics, type: :boolean
    has_scope :monthly, type: :boolean
    has_scope :quarterly, type: :boolean
    has_scope :yearly, type: :boolean
    has_scope :ytd, type: :boolean

    def perform(collection:, params:)
      Rails.logger.debug { "[KpiQuery] perform called with collection class: #{collection.klass.name}, params: #{params.inspect}" }
      result = apply_scopes(collection, params)
      Rails.logger.debug { "[KpiQuery] perform returning collection with SQL: #{result.to_sql}" }
      result
    end
  end

  def initialize(user:)
    @user = user
  end

  # Lists portfolio companies (Investors with category 'Portfolio Company').
  def list_portfolio_companies(scope: nil, query: {}, sort: nil)
    ransack_query = query || {}
    ransack_query[:s] ||= sort if sort.present?

    relation = Pundit.policy_scope(@user, Investor).portfolio_companies
    relation = relation.send(scope) if scope.present? && Investor.respond_to?(scope)
    companies = relation.ransack(ransack_query).result

    companies.map do |c|
      {
        id: c.id,
        name: c.investor_name,
        category: c.category,
        city: c.city,
        tags: c.tag_list
      }
    end
  end

  # Gets basic details for a specific portfolio company.
  def get_portfolio_company_details(portfolio_company_id:)
    company = Pundit.policy_scope(@user, Investor).portfolio_companies.find_by(id: portfolio_company_id)
    return "Portfolio Company not found or access denied" unless company

    {
      id: company.id,
      name: company.investor_name,
      category: company.category,
      primary_email: company.primary_email,
      tags: company.tag_list.to_s,
      city: company.city,
      amount_invested: company.amount_invested.format,
      last_interaction: (I18n.l(company.last_interaction_date) if company.last_interaction_date.present?)
    }
  end

  # Lists valuations for a portfolio company.
  def list_valuations(portfolio_company_id:, scope: nil, query: {}, sort: nil)
    company = Pundit.policy_scope(@user, Investor).portfolio_companies.find_by(id: portfolio_company_id)
    return [] unless company

    ransack_query = query || {}
    ransack_query[:s] ||= sort if sort.present?

    relation = Pundit.policy_scope(@user, Valuation).includes(:portfolio_company, :entity, :investment_instrument).where(owner: company)
    relation = relation.send(scope) if scope.present? && Valuation.respond_to?(scope)
    valuations = relation.ransack(ransack_query).result
    valuations.map do |v|
      {
        id: v.id,
        entity: v.entity.name,
        owner: v.portfolio_company&.investor_name,
        instrument: v.investment_instrument&.name,
        valuation_date: (I18n.l(v.valuation_date) if v.valuation_date),
        per_share_value: (v.per_share_value_cents / 100.0),
        currency: v.currency,
        synthetic: v.synthetic
      }
    end
  end

  # rubocop:disable Metrics/CyclomaticComplexity
  # Lists portfolio investments for a portfolio company.
  def list_portfolio_investments(portfolio_company_id:, scope: nil, query: {}, sort: nil)
    company = Pundit.policy_scope(@user, Investor).portfolio_companies.find_by(id: portfolio_company_id)
    return [] unless company

    ransack_query = query || {}
    ransack_query[:s] ||= sort if sort.present?

    relation = Pundit.policy_scope(@user, PortfolioInvestment).includes(:fund, :portfolio_company, :investment_instrument).where(portfolio_company_id: company.id)

    relation = relation.send(scope) if scope.present? && PortfolioInvestment.respond_to?(scope)

    investments = relation.ransack(ransack_query).result
    investments.map do |i|
      {
        id: i.id,
        fund: i.fund&.name,
        portfolio_company: i.portfolio_company&.investor_name,
        instrument: i.investment_instrument&.name,
        investment_date: (I18n.l(i.investment_date) if i.investment_date),
        conversion_date: (I18n.l(i.conversion_date) if i.conversion_date),
        instrument_currency: i.investment_instrument&.currency.to_s,
        amount: i.amount.format,
        ex_expenses_amount: i.ex_expenses_amount.format,
        net_amount: i.net_amount.format,
        quantity: i.quantity,
        valuation: i.valuation&.to_s,
        sold_quantity: (i.sold_quantity if i.buy?),
        transfer_quantity: (i.transfer_quantity if i.buy?),
        transfer_amount: (i.transfer_amount.format if i.buy?),
        net_quantity: (i.net_quantity if i.buy?),
        cost_of_remaining: (i.cost_of_remaining if i.buy?),
        cost_per_share: (i.cost.format if i.buy?),
        fmv: i.fmv.format,
        sale_price_per_share: (i.sale_price_per_share.format if i.sell?),
        cost_of_sold: (i.cost_of_sold.format if i.sell?),
        cost_of_sold_per_share: (i.cost_of_sold_per_share.format if i.sell?),
        gain: (i.gain.format if i.sell?),
        unrealized_gain: (i.unrealized_gain.format unless i.sell?),
        startup: i.startup,
        proforma: i.proforma
      }
    end
  end
  # rubocop:enable Metrics/CyclomaticComplexity

  # Lists KPIs for portfolio companies.
  def list_portfolio_kpis(portfolio_company_ids:, scope: nil, query: {}, sort: nil)
    companies = Pundit.policy_scope(@user, Investor).portfolio_companies.where(id: portfolio_company_ids)
    return [] if companies.empty?

    ransack_query = query || {}
    ransack_query[:s] ||= sort if sort.present?

    Rails.logger.debug { "[KpiQuery Debug] Incoming scope: #{scope.inspect}" }
    relation = Kpi.where(portfolio_company_id: companies.pluck(:id)).includes(:kpi_report, :portfolio_company)
    if scope.present?
      # If scope is a comma-separated string, convert to hash for KpiQuery
      scope_params = if scope.is_a?(String)
                       scope.split(',').each_with_object({}) { |s, h| h[s.strip.to_sym] = "true" }
                     elsif scope.is_a?(Symbol)
                       { scope => "true" }
                     else
                       scope # Assume it's already a hash or compatible
                     end

      Rails.logger.debug { "[KpiQuery Debug] Applying scopes with params: #{scope_params.inspect}" }
      relation = KpiQuery.new.perform(collection: relation, params: scope_params)
    end
    kpis = relation.ransack(ransack_query).result
    Rails.logger.debug { "[KpiQuery Debug] SQL after ransack: #{kpis.to_sql}" }
    kpis.map do |k|
      {
        id: k.id,
        portfolio_company: k.portfolio_company&.investor_name,
        as_of: (I18n.l(k.kpi_report.as_of) if k.kpi_report&.as_of),
        name: k.name,
        period: k.kpi_report&.period,
        value: k.value,
        display_value: k.display_value,
        percentage_change: "#{k.percentage_change}%",
        notes: k.notes,
        source: k.source,
        tag_list: k.kpi_report&.tag_list
      }
    end
  end

  # Lists portfolio report extracts for a portfolio company.
  def list_portfolio_report_extracts(portfolio_company_id:, query: {}, sort: nil)
    company = Pundit.policy_scope(@user, Investor).portfolio_companies.find_by(id: portfolio_company_id)
    return [] unless company

    ransack_query = query || {}
    ransack_query[:s] ||= sort if sort.present?

    extracts = company.portfolio_report_extracts.ransack(ransack_query).result
    extracts.map do |e|
      {
        id: e.id,
        report_date: e.report_date,
        content: e.content,
        category: e.category
      }
    end
  end

  # Lists fund ratios.
  #
  # @param portfolio_company_id [Integer, nil] Filter by portfolio company ID.
  # @param query [Hash] Ransack query parameters.
  # @param sort [String, nil] Sort string.
  # @return [Array<Hash>] List of fund ratios.
  def list_fund_ratios(portfolio_company_id: nil, query: {}, sort: nil)
    ransack_query = query || {}
    ransack_query[:s] ||= sort if sort.present?
    ransack_query[:owner_id_eq] = portfolio_company_id if portfolio_company_id.present?
    ransack_query[:owner_type_eq] = 'Investor' if portfolio_company_id.present?

    ratios = Pundit.policy_scope(@user, FundRatio).includes(:fund, :portfolio_scenario).ransack(ransack_query).result
    ratios.map do |r|
      {
        id: r.id,
        fund_id: r.fund_id,
        fund_name: r.fund&.name,
        name: r.name,
        value: r.value,
        display_value: r.display_value,
        end_date: r.end_date,
        latest: r.latest,
        owner_type: r.owner_type,
        owner_id: r.owner_id,
        scenario: r.scenario,
        portfolio_scenario: r.portfolio_scenario&.name
      }
    end
  end

  # Lists documents associated with the portfolio company.
  def list_documents(portfolio_company_id:, scope: nil, query: {}, sort: nil)
    company = Pundit.policy_scope(@user, Investor).portfolio_companies.find_by(id: portfolio_company_id)
    return [] unless company

    ransack_query = query || {}
    ransack_query[:s] ||= sort if sort.present?

    # Documents are often associated through WithFolder or specific polymorphic associations
    # Assuming documents can be found via the company's entity or specific document relation
    relation = Pundit.policy_scope(@user, Document).where(owner: company)
    relation = relation.send(scope) if scope.present? && Document.respond_to?(scope)
    documents = relation.ransack(ransack_query).result

    documents.map do |d|
      {
        id: d.id,
        name: d.name,
        folder: d.folder&.full_path,
        tags: d.tag_list,
        owner_tag: d.owner_tag,
        created_at: (I18n.l(d.created_at) if d.created_at),
        belongs_to: d.owner_type,
        from_template: d.from_template&.name,
        download_allowed: d.download,
        embed_allowed: d.embed,
        printing_allowed: d.printing,
        original_allowed: d.orignal,
        public_visibility: d.public_visibility,
        send_email_allowed: d.send_email,
        uploaded_by: "#{d.user&.full_name} (#{d.user&.email})",
        details: d.text,
        esign_status: d.esign_status&.titleize,
        esign_on_page: d.display_on_page&.titleize,
        esign_order_forced: d.force_esign_order
      }
    end
  end
end

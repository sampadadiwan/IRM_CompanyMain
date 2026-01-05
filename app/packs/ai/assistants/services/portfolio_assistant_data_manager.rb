# PortfolioAssistantDataManager
#
# Handles business logic and data retrieval for the PortfolioAssistant.
# Focused on portfolio company specific data: valuations, investments, KPIs, and documents.
#
class PortfolioAssistantDataManager
  include WithFilterParams

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
  def list_portfolio_companies(scope: nil, query: {}, sort: nil, limit: nil, aggregate: nil)
    Rails.logger.debug { "[PortfolioAssistantDataManager] list_portfolio_companies called with scope: #{scope.inspect}, query: #{query.inspect}, sort: #{sort.inspect}, limit: #{limit.inspect}, aggregate: #{aggregate.inspect}" }
    ransack_query = query || {}
    ransack_query[:s] ||= sort if sort.present?

    relation = Pundit.policy_scope(@user, Investor).portfolio_companies
    relation = relation.send(scope) if scope.present? && Investor.respond_to?(scope)
    results = relation.ransack(ransack_query).result

    return FundAssistantDataManager.new(user: @user).send(:perform_aggregation, results, aggregate, field: query&.dig(:aggregate_field), group_by: query&.dig(:group_by)) if aggregate.present?

    results = results.limit(limit) if limit.present?

    results.map do |c|
      {
        id: c.id,
        name: c.investor_name,
        category: c.category,
        city: c.city,
        tags: c.tag_list,
        view_link: "/investors/#{c.id}"
      }
    end
  end

  # Gets basic details for a specific portfolio company.
  def get_portfolio_company_details(portfolio_company_id:)
    Rails.logger.debug { "[PortfolioAssistantDataManager] get_portfolio_company_details called with portfolio_company_id: #{portfolio_company_id.inspect}" }
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
      last_interaction: (I18n.l(company.last_interaction_date) if company.last_interaction_date.present?),
      view_link: "/investors/#{company.id}"
    }
  end

  # Lists valuations for a portfolio company.
  def list_valuations(portfolio_company_id:, scope: nil, query: {}, sort: nil, limit: nil, aggregate: nil)
    Rails.logger.debug { "[PortfolioAssistantDataManager] list_valuations called with portfolio_company_id: #{portfolio_company_id.inspect}, scope: #{scope.inspect}, query: #{query.inspect}, sort: #{sort.inspect}, limit: #{limit.inspect}, aggregate: #{aggregate.inspect}" }
    company = Pundit.policy_scope(@user, Investor).portfolio_companies.find_by(id: portfolio_company_id)
    return [] unless company

    ransack_query = query || {}
    ransack_query[:s] ||= sort if sort.present?

    relation = Pundit.policy_scope(@user, Valuation).includes(:portfolio_company, :entity, :investment_instrument).where(owner: company)
    relation = relation.send(scope) if scope.present? && Valuation.respond_to?(scope)
    results = relation.ransack(ransack_query).result

    return FundAssistantDataManager.new(user: @user).send(:perform_aggregation, results, aggregate, field: query&.dig(:aggregate_field), group_by: query&.dig(:group_by)) if aggregate.present?

    results = results.limit(limit) if limit.present?

    results.map do |v|
      {
        id: v.id,
        entity: v.entity.name,
        owner: v.portfolio_company&.investor_name,
        instrument: v.investment_instrument&.name,
        valuation_date: (I18n.l(v.valuation_date) if v.valuation_date),
        per_share_value: (v.per_share_value_cents / 100.0),
        currency: v.currency,
        synthetic: v.synthetic,
        view_link: "/valuations/#{v.id}"
      }
    end
  end

  # rubocop:disable Metrics/PerceivedComplexity, Metrics/MethodLength
  # Lists portfolio investments for a portfolio company.
  def list_portfolio_investments(portfolio_company_id:, scope: nil, query: {}, sort: nil, limit: nil, aggregate: nil)
    Rails.logger.debug { "[PortfolioAssistantDataManager] list_portfolio_investments called with portfolio_company_id: #{portfolio_company_id.inspect}, scope: #{scope.inspect}, query: #{query.inspect}, sort: #{sort.inspect}, limit: #{limit.inspect}, aggregate: #{aggregate.inspect}" }
    company = Pundit.policy_scope(@user, Investor).portfolio_companies.find_by(id: portfolio_company_id)
    return [] unless company

    ransack_query = query || {}
    ransack_query[:s] ||= sort if sort.present?

    relation = Pundit.policy_scope(@user, PortfolioInvestment).includes(:fund, :portfolio_company, :investment_instrument).where(portfolio_company_id: company.id)

    relation = relation.send(scope) if scope.present? && PortfolioInvestment.respond_to?(scope)

    results = relation.ransack(ransack_query).result

    return FundAssistantDataManager.new(user: @user).send(:perform_aggregation, results, aggregate, field: query&.dig(:aggregate_field), group_by: query&.dig(:group_by)) if aggregate.present?

    results = results.limit(limit) if limit.present?

    results.map do |i|
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
        proforma: i.proforma,
        view_link: "/portfolio_investments/#{i.id}"
      }
    end
  end
  # rubocop:enable Metrics/PerceivedComplexity, Metrics/MethodLength

  # Lists KPIs for portfolio companies.
  def list_portfolio_kpis(portfolio_company_ids:, scope: :actuals, query: {}, sort: nil, limit: nil, aggregate: nil)
    Rails.logger.debug { "[PortfolioAssistantDataManager] list_portfolio_kpis called with portfolio_company_ids: #{portfolio_company_ids.inspect}, scope: #{scope.inspect}, query: #{query.inspect}, sort: #{sort.inspect}, limit: #{limit.inspect}, aggregate: #{aggregate.inspect}" }
    companies = Pundit.policy_scope(@user, Investor).portfolio_companies.where(id: portfolio_company_ids)
    return [] if companies.empty?

    ransack_query = (query || {}).with_indifferent_access
    ransack_query[:s] ||= sort if sort.present?

    # Default kpi_report_as_of to 12 months ago if not provided
    ransack_query[:kpi_report_as_of_gteq] = 12.months.ago.to_date unless ransack_has_attr?(ransack_query, :kpi_report_as_of)

    Rails.logger.debug { "[KpiQuery Debug] Incoming scope: #{scope.inspect}" }
    relation = Kpi.where(portfolio_company_id: companies.pluck(:id)).includes(:portfolio_company)

    scope ||= "monthly,actuals"
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
    results = relation.joins(:kpi_report).includes(:kpi_report, :investor_kpi_mappings).ransack(ransack_query).result

    return FundAssistantDataManager.new(user: @user).send(:perform_aggregation, results, aggregate, field: query&.dig(:aggregate_field), group_by: query&.dig(:group_by)) if aggregate.present?

    results = results.limit(limit) if limit.present?

    Rails.logger.debug { "[KpiQuery Debug] SQL after ransack: #{results.to_sql}" }
    results.map do |k|
      {
        id: k.id,
        portfolio_company: k.portfolio_company&.investor_name,
        as_of: (I18n.l(k.kpi_report.as_of) if k.kpi_report&.as_of),
        name: k.name,
        period: k.kpi_report&.period,
        value: k.value,
        # display_value: k.display_value,
        percentage_change: "#{k.percentage_change}%",
        # notes: k.notes,
        # source: k.source,
        tag_list: k.kpi_report&.tag_list,
        view_link: "/kpis/#{k.id}"
      }
    end
  end

  # Lists fund ratios.
  #
  # @param portfolio_company_id [Integer, nil] Filter by portfolio company ID.
  # @param query [Hash] Ransack query parameters.
  # @param sort [String, nil] Sort string.
  # @param limit [Integer, nil] Maximum number of records to return.
  # @param aggregate [String, nil] Type of aggregation to perform.
  # @return [Array<Hash>] List of fund ratios.
  def list_fund_ratios(portfolio_company_id: nil, query: {}, sort: nil, limit: nil, aggregate: nil)
    Rails.logger.debug { "[PortfolioAssistantDataManager] list_fund_ratios called with portfolio_company_id: #{portfolio_company_id.inspect}, query: #{query.inspect}, sort: #{sort.inspect}, limit: #{limit.inspect}, aggregate: #{aggregate.inspect}" }
    ransack_query = query || {}
    ransack_query[:s] ||= sort if sort.present?
    ransack_query[:owner_id_eq] = portfolio_company_id if portfolio_company_id.present?
    ransack_query[:owner_type_eq] = 'Investor' if portfolio_company_id.present?

    relation = Pundit.policy_scope(@user, FundRatio).includes(:fund, :portfolio_scenario)
    results = relation.ransack(ransack_query).result

    return FundAssistantDataManager.new(user: @user).send(:perform_aggregation, results, aggregate, field: query&.dig(:aggregate_field), group_by: query&.dig(:group_by)) if aggregate.present?

    results = results.limit(limit) if limit.present?

    results.map do |r|
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
        portfolio_scenario: r.portfolio_scenario&.name,
        view_link: "/fund_ratios/#{r.id}"
      }
    end
  end

  # Lists documents associated with the portfolio company.
  def list_documents(portfolio_company_id:, scope: nil, query: {}, sort: nil, limit: nil)
    Rails.logger.debug { "[PortfolioAssistantDataManager] list_documents called with portfolio_company_id: #{portfolio_company_id.inspect}, scope: #{scope.inspect}, query: #{query.inspect}, sort: #{sort.inspect}, limit: #{limit.inspect}" }
    company = Pundit.policy_scope(@user, Investor).portfolio_companies.find_by(id: portfolio_company_id)
    return [] unless company

    ransack_query = query || {}
    ransack_query[:s] ||= sort if sort.present?

    # Documents are often associated through WithFolder or specific polymorphic associations
    # Assuming documents can be found via the company's entity or specific document relation
    relation = Pundit.policy_scope(@user, Document).where(owner: company).or(
      Pundit.policy_scope(@user, Document).where(owner: company.portfolio_kpi_reports)
    )
    relation = relation.send(scope) if scope.present? && Document.respond_to?(scope)
    documents = relation.ransack(ransack_query).result
    documents = documents.limit(limit) if limit.present?

    documents.map do |d|
      {
        id: d.id,
        name: d.name,
        folder: d.folder&.full_path,
        tags: d.tag_list,
        owner_tag: d.owner_tag,
        created_at: (I18n.l(d.created_at) if d.created_at),
        belongs_to: d.owner_type,
        details: d.text,
        esign_status: d.esign_status&.titleize,
        esign_on_page: d.display_on_page&.titleize,
        esign_order_forced: d.force_esign_order,
        download_file_url: d.file.url,
        view_link: "/documents/#{d.id}"
      }
    end
  end

  # Gets details and text for a specific document.
  def get_document(document_id: nil, name: nil)
    Rails.logger.debug { "[PortfolioAssistantDataManager] get_document called with document_id: #{document_id.inspect}, name: #{name.inspect}" }
    scope = Pundit.policy_scope(@user, Document)
    document = if document_id.present?
                 scope.find_by(id: document_id)
               elsif name.present?
                 # Try exact match first, then partial match
                 scope.find_by(name: name) || scope.where("name LIKE ?", "%#{name}%").first
               end

    return "Document not found or access denied" unless document

    {
      id: document.id,
      name: document.name,
      folder: document.folder&.full_path,
      tags: document.tag_list,
      owner_tag: document.owner_tag,
      created_at: (I18n.l(document.created_at) if document.created_at),
      belongs_to: document.owner_type,
      owner_name: (document.owner.respond_to?(:name) ? document.owner.name : document.owner&.to_s),
      file_url: document.file.url,
      view_link: "/documents/#{document.id}"
    }
  end

  # Analyzes documents using RubyLLM and their file_urls.
  def analyze_documents(prompt:, document_ids: [], document_names: [])
    Rails.logger.debug { "[PortfolioAssistantDataManager] analyze_documents called with prompt: #{prompt.inspect}, document_ids: #{document_ids.inspect}, document_names: #{document_names.inspect}" }
    scope = Pundit.policy_scope(@user, Document)
    documents = []

    documents += scope.where(id: document_ids).to_a if document_ids.present?

    if document_names.present?
      document_names.each do |name|
        doc = scope.find_by(name: name) || scope.where("name LIKE ?", "%#{name}%").first
        documents << doc if doc
      end
    end

    documents.uniq!

    return "No documents found to analyze." if documents.empty?

    # Prepare file URLs for RubyLLM
    attachments = documents.map { |d| { d.extension.to_sym => d.file.url } }

    chat = RubyLLM.chat
    response = chat.ask prompt, with: attachments
    response.content
  end

  # Generates a cap table for a portfolio company.
  #
  # @param portfolio_company_id [Integer] The ID of the portfolio company.
  # @param funding_rounds [Array<String>, nil] Optional funding rounds to filter by.
  # @param group_by_field [String, Symbol] Field to group the cap table by.
  # @return [Array<Hash>] The cap table data.
  def get_cap_table(portfolio_company_id:, funding_rounds: nil, group_by_field: :investor_name)
    Rails.logger.debug { "[PortfolioAssistantDataManager] get_cap_table called with portfolio_company_id: #{portfolio_company_id.inspect}, funding_rounds: #{funding_rounds.inspect}, group_by_field: #{group_by_field.inspect}" }
    company = Pundit.policy_scope(@user, Investor).portfolio_companies.find_by(id: portfolio_company_id)
    return "Portfolio Company not found or access denied" unless company

    # If funding_rounds not provided, we might want to get all funding rounds for that company
    rounds = funding_rounds
    rounds = Investment.where(portfolio_company_id: company.id).pluck(:funding_round).uniq if rounds.blank?

    return [] if rounds.blank?

    Investment.generate_cap_table(rounds, company.id, group_by_field: group_by_field.to_sym)
  end

  # Gets investments in cap table across portfolio companies.
  #
  # @param portfolio_company_ids [Array<Integer>] List of portfolio company IDs.
  # @param query [Hash] Optional Ransack query hash.
  # @param sort [String] Optional sort string.
  # @param limit [Integer, nil] Maximum number of records to return.
  # @return [Array<Hash>] List of investments.
  def get_investments_in_cap_table(portfolio_company_ids:, query: {}, sort: nil, limit: nil)
    Rails.logger.debug { "[PortfolioAssistantDataManager] get_investments_in_cap_table called with portfolio_company_ids: #{portfolio_company_ids.inspect}, query: #{query.inspect}, sort: #{sort.inspect}, limit: #{limit.inspect}" }
    companies = Pundit.policy_scope(@user, Investor).portfolio_companies.where(id: portfolio_company_ids)
    return [] if companies.empty?

    ransack_query = query || {}
    ransack_query[:s] ||= sort if sort.present?

    investments = Investment.where(portfolio_company_id: companies.pluck(:id)).ransack(ransack_query).result
    investments = investments.limit(limit) if limit.present?

    investments.map do |i|
      {
        id: i.id,
        portfolio_company: i.portfolio_company&.investor_name,
        category: i.category,
        investor_name: i.investor_name,
        investment_type: i.investment_type,
        funding_round: i.funding_round,
        currency: i.currency,
        price: i.price.format,
        investment_date: (I18n.l(i.investment_date) if i.investment_date),
        amount: i.amount.format,
        quantity: i.quantity,
        view_link: "/investments/#{i.id}"
      }
    end
  end
end
